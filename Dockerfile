# syntax=docker/dockerfile:1
# check=error=true

# The application container. It needs a MySQL server alongside it — see
# compose.yaml, which is the supported way to run this.
#
# This used to be a genuinely single-container image on SQLite, which made
# self-hosting a single `docker run`. Moving to MySQL trades that away: an
# operator now runs two containers and has a database to back up, upgrade and
# secure. What it buys is a database that handles concurrent writers properly
# and that most people already know how to operate, host, and replicate.
#
# Still only one *application* process: Solid Queue runs inside Puma, so the
# reminder sweep is not a separate service somebody can forget to start.
#
# Build from the REPOSITORY ROOT, not from web/:
#
#   docker compose up -d --build
#
# The rules dataset is baked in rather than fetched at runtime, so an instance
# with no outbound network still knows every renewal rule it shipped with.

ARG RUBY_VERSION=3.4.10
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

# libmariadb3 provides the client library mysql2 links against at runtime.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips libmariadb3 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so" \
    # Runs the Solid Queue supervisor inside the Puma process, so the reminder
    # sweep is not a separate service somebody can forget to start. The sweep
    # is the product; it must not be optional.
    SOLID_QUEUE_IN_PUMA="true"

# ---- build ------------------------------------------------------------------

FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config \
                                               default-libmysqlclient-dev && \
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
# storage/ now holds only encrypted attachments — the databases live in MySQL.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p db log storage tmp && \
    chown -R rails:rails db log storage tmp
USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
