# syntax=docker/dockerfile:1
# check=error=true

# One container: web, background jobs, and the database. That is the whole
# point — the self-hosted image is a credibility signal, and a credibility
# signal that needs a Postgres box, a Redis box and a worker process is not
# signalling much. SQLite plus Solid Queue running inside Puma collapses it to
# a single `docker run`.
#
# Build from the REPOSITORY ROOT, not from web/:
#
#   docker build -t renewaru .
#   docker run -d -p 8080:80 \
#     -e SECRET_KEY_BASE="$(openssl rand -hex 64)" \
#     -e ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY="$(openssl rand -hex 32)" \
#     -e ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY="$(openssl rand -hex 32)" \
#     -e ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT="$(openssl rand -hex 32)" \
#     -v renewaru-data:/rails/storage \
#     renewaru
#
# The rules dataset is baked in rather than fetched at runtime, so an instance
# with no outbound network still knows every renewal rule it shipped with.

ARG RUBY_VERSION=3.3.6
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips sqlite3 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so" \
    # Runs the Solid Queue supervisor inside the Puma process. This is what
    # makes one container enough — and the reminder sweep is the product, so
    # it must not be the thing an operator forgets to start.
    SOLID_QUEUE_IN_PUMA="true"

# ---- build ------------------------------------------------------------------

FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY web/Gemfile web/Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

COPY web .

# The dataset and its loader sit one level above Rails.root, matching the
# repository layout, so no path configuration is needed at runtime.
COPY lib /lib
COPY rules /rules

RUN bundle exec bootsnap precompile app/ lib/

# A throwaway key: this only has to be present for asset compilation, and
# baking a real one into an image layer would be a good way to leak it.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# ---- final ------------------------------------------------------------------

FROM base

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails
COPY --from=build /lib/renewaru /lib/renewaru
COPY --from=build /rules /rules

# Non-root, and owning only what it must be able to write.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p db log storage tmp && \
    chown -R rails:rails db log storage tmp
USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
