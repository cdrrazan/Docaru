# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is, in one paragraph

**A self-hosted, browser-encrypted vault for a household's documents, which also knows when the ones
with deadlines need renewing.** Storage is the product: most of what a household keeps — a degree
certificate, a birth certificate, a land deed — never expires at all, and exists in here so it can be
reached from another city rather than from a drawer. The renewal engine is the layer on top, and it
is what makes the vault worth opening rather than the reason it exists. If you find yourself treating
an expiry date as mandatory, or the dataset as the point, that is the bug — see the git history for
the commit that inverted it back.

Two things in one repository, deliberately kept apart:

- **`rules/`, `schema/`, `lib/`, `bin/`, `test/`** — the public renewal-rule dataset and its plain-Ruby
  toolchain. **Ruby 3.x, no gems, no bundler, no network.** Never add a dependency here; the constraint
  exists so a contributor can fix a typo in a YAML file without installing anything.
- **`web/`** — a Rails 8.1 application that consumes the dataset. Gems live here only.

The dataset is the public artefact and sits at the repository root for that reason. Do not move it into
`web/`, and do not load rules into ActiveRecord — the split between the public plane (flat files, edited by
PR, no user data) and the private plane (the app's MySQL database) is structural, not stylistic.

`renewal-vault-spec.md` is the product spec. Code comments reason against it by section — "spec §6",
"§7", "§13" — so it is the authority on *why* when a comment cites it. `SCHEMA.md` documents four
deliberate deviations from its §6.

## Commands

Dataset (from repo root):

```sh
ruby bin/validate                      # schema + consistency + provenance + feasibility
ruby bin/validate --strict             # warnings become failures
ruby bin/validate --max-age-days 365   # what CI runs
ruby bin/build [out-dir]               # static playbook site + site/rules.json (default site/)
ruby test/schema_test.rb               # the dataset's whole test suite
```

Application (from `web/`):

```sh
bin/setup                              # bundle, db:prepare, then starts bin/dev
bin/setup --skip-server
bin/rails db:seed                      # demo household; development and test only, idempotent
bin/rails server
bin/rails test                         # Minitest — this app does NOT use RSpec
bin/rails test test/models/document_test.rb          # one file
bin/rails test test/models/document_test.rb:42       # one test by line
bin/rubocop                            # rubocop-rails-omakase
bin/brakeman --no-pager
bin/bundler-audit
bin/importmap audit
bin/ci                                 # everything above, via config/ci.rb
```

Needs MySQL 8.0+/MariaDB 10.6+. Defaults to `docaru`/`docaru` on `127.0.0.1`; override with
`DATABASE_HOST`/`DATABASE_USERNAME`/`DATABASE_PASSWORD`. Tests run parallel and use four logical databases
per worker (primary, cache, queue, cable), so the test user needs create rights — CI uses `root`.

Self-hosting: `cp .env.example .env && docker compose up -d --build`. The Docker image has never actually
been built (no daemon available during development) — see CHANGELOG.md.

## The one derived number

Everything in `lib/` exists to compute this, and every layer above renders it:

```
start_by = expires_on − processing.worst_case − max(obtain_lead_days of prerequisites) − buffer_days
```

**Always `worst_case`, never `typical`.** A date from the median is correct for the median applicant and
useless for the tail — which is who a missed deadline actually destroys. If you find code anchoring to
`typical` or to the expiry date, that is a bug.

## Dataset architecture (`lib/renewaru/`)

`Dataset.load` globs `rules/**/*.yml` → `Rule` per file → `rule.resolve(context)` → `Rule::Resolved` →
`Timeline`.

- **`Rule`** — one YAML file. `contexts` is `"domestic"` plus every key of `abroad_overrides`; each
  (rule, context) pair is one playbook page and one SEO unit.
- **`Rule::Resolved`** — override wins field by field, base rule fills the rest. Note `status`: an override
  cannot inherit `verified` from its parent, so a verified base cannot launder an unchecked branch.
- **`Timeline`** — `feasible?`, `shortfall_days`, `covered_by_grace?`, `verdict`, and the window phrasing.
  Sentence phrasing lives here, not in views, so the Rails app and the static generator cannot describe the
  same rule differently.
- **`Playbook`** — renders one resolved rule as complete server-side HTML, no JS, no external requests.
- **`SchemaValidator`** — hand-rolled JSON Schema 2020-12 subset. `schema/renewal-rule.schema.json` is the
  authority on what validates; `SCHEMA.md` is the authority on what fields mean.

`bin/validate` enforces what JSON Schema cannot: official-domain sourcing before `verified`, verification
staleness (365 days), directory/filename matching `country_code`/`document_kind`, and **feasibility** —
where total lead time exceeds the renewal window it *reports* rather than rejects, because that is a true
fact about the world and the one a reader most needs.

## Rule file conventions

- Path is `rules/<lowercase country_code>/<document_kind with dashes>.yml`; the validator enforces it.
- `document_kind` is a closed enum in the JSON schema — extending it is a deliberate schema PR, because the
  app needs UI for every kind that exists.
- `window_*_days_before` count backwards from expiry, so "opens" is the larger number. A negative
  `window_closes_days_before` is a grace period after expiry.
- `status: draft` is the default and every rendering surface must show the warning. Nothing is verified yet.
- `obtain_lead_days` on a prerequisite is plan time, not a checklist item. Omitting it produces a start date
  that is confidently too late.

## Application architecture (`web/`)

`config/initializers/renewaru_dataset.rb` requires `lib/renewaru/dataset` from outside the Rails tree —
explicitly, not autoloaded, because Rails does not own it.

- **`RuleCatalog`** — the only bridge to the dataset. Reloads per call in development, memoised elsewhere.
  `normalise_context` is the important part: an unknown origin falls back to the generic *abroad* timings,
  never to domestic, since silently returning domestic gives someone abroad a date months too late.
- **`Document`** — the private-plane record. `kind`/`issuing_country`/`expires_on` are stored in the clear
  because the server must compute dates; `identifier` and `notes` are `encrypts`ed. `status`/`severity`
  drive dashboard ordering and deliberately mirror `RenewalCalculation#status`.
  **`expires_on` is nullable and that is load-bearing.** A document without one is `:stored` — a
  finished state, not a missing field — and it is the majority case. `:stored` and `:unknown` are
  different answers: `:unknown` means it expires and no rule exists, `:stored` means there is nothing
  to watch and never will be. Anything reading `expires_on` must handle nil; `ReminderSchedule`,
  `PrerequisiteChain` and `sort_key` each do so explicitly.
- **`DocumentsController#index`** — the vault: browse and search by label, kind, country or person,
  grouped by person. Search deliberately excludes `identifier` and `notes`, which are encrypted so the
  server cannot read them; the limit is stated in the UI rather than left as a query that never matches.
  The dashboard answers "what needs doing"; this answers "where is Aama's citizenship certificate",
  and for the documents that never expire only the second question is ever asked.
- **`ReminderSchedule`** — derived on every sweep, never persisted, so correcting an expiry date reshapes
  all future alerts with no backfill. Five stages anchored to `start_by`, cascading *past* it (the failure
  mode is procrastination, not amnesia); a `FALLBACK` expiry-anchored set when no rule exists.
- **`DeliverRemindersJob`** — nightly at 7am via `config/recurring.yml`, Solid Queue running inside Puma.
  This job is the product. It sends at most one message per document per sweep, claims the stage in a
  transaction before sending, and swallows per-document errors so one bad row cannot stop the sweep.
- **`PrerequisiteChain`** — joins the dataset's dependency edges to what the household actually holds, and
  flags when one document lapsing will block another's renewal.
- **`RenewalCalculation`** — the anonymous calculator. ActiveModel, not ActiveRecord, on purpose: nothing is
  stored, and the question lives in the URL so answers are shareable.
- **`MachineReadableZone`** — ICAO 9303 TD3/TD1 parser with check-digit validation. Not general OCR; the
  check digits are the whole reason it is trustworthy enough to write an expiry date from.
- **`MachineReadableZone` repair** — a camera misreads `O` for `0` in the date fields. Digit-shaped letters
  are mapped to digits *only* inside the runs the standard defines as numeric, and the check digits rule on
  the result. Deliberately one deterministic candidate, never a search: trying substitutions until one
  satisfies a one-digit checksum finds a passing answer about one time in ten whether or not it is true.
- **Vault** — `app/javascript/controllers/vault_controller.js` does AES-GCM in the browser with a PBKDF2 key
  from a passphrase that never leaves the tab. `AttachmentsController` and `Attachment` handle opaque bytes
  only. **Never add server-side decryption, thumbnailing, resizing, or filename storage.**
- **`app/views/pwa/service-worker.js`** — caches by **allowlist**, never denylist, so a private route added
  later is excluded by default. Caching a dashboard would write document metadata into CacheStorage, where it
  outlives signing out. There is a test that fails if a private path enters the allowlist.
- **`PushSubscription` / `DeliverPushJob`** — additive to email, never a replacement. Email is sent first and
  unconditionally. Wording lives in `ReminderNotification` and is shared with `ReminderMailer`, so the two
  channels cannot describe the same deadline differently — the same argument as `Timeline#verdict`.
- **`Paddle` / `Subscription` / `PaddleWebhooksController`** — Paddle because Stripe will not onboard a
  Nepal-based business; it is also merchant of record, so it remits VAT wherever the buyer is. The plan moves
  **on the webhook, never on the redirect back**. Webhooks are idempotent by unique event id and guarded
  against out-of-order delivery by `last_event_at`. `past_due` and `paused` stay entitled on purpose.

Authorisation is by scoping: `Authentication#household` establishes the scope once and records are found
*through* it, so cross-household access is a 404 by construction. Keep that pattern.

## Conventions worth respecting

- Tests are **Minitest with fixtures** (`web/test/`), Rails default. Do not introduce RSpec here.
- Style is `rubocop-rails-omakase`, unmodified.
- Reminders and playbooks are never gated by plan (`Household#alerting?` is unconditionally true), and no
  billing state stops one either. Paywalling the safety feature poisons the trust the product rests on, and
  somebody whose card fails while abroad is exactly who needs the alert. A test walks every billing status
  and asserts it; if you find yourself making `alerting?` conditional, that is the bug.
- Public pages must stay crawlable *and* unambiguous. Every playbook declares a canonical URL, an origin that
  is not a country is a 404 rather than a silent fallback to domestic, and answered calculator results are
  `noindex` because there is one URL per expiry date.
- `db/seeds.rb` is guarded to `Rails.env.local?`. `db:prepare` runs seeds on a fresh database and the Docker
  entrypoint runs `db:prepare`, so an unguarded seed plants a known password on every new instance.
  Its proportions are deliberate — six of thirteen documents have no expiry, because that is what a real
  drawer looks like and the demo argues the product's thesis by being shaped correctly.
- Self-hosting is the default deployment, not a credibility signal. The reason somebody chooses this over
  Drive is that nobody else can read it, so anything that assumes a hosted instance — a required external
  service, a phone-home, a feature that degrades without an account — undercuts the whole proposition.
- Playbook pages are server-rendered with no client-side rendering, because organic search is the
  acquisition channel and a crawler cannot read a client-rendered page.
- Comments in this codebase explain *why*, often at length. Match that when editing; do not strip them.

## CI

- `.github/workflows/validate.yml` — dataset tests, `bin/validate --max-age-days 365`, `bin/build`. Also runs
  weekly on a schedule, because rules go stale without anyone touching the repo.
- `.github/workflows/app.yml` — Rails tests against MySQL 8.4, RuboCop, Brakeman, bundler-audit, importmap
  audit. Runs with `working-directory: web`.
- `.github/workflows/pages.yml` — `workflow_dispatch` only until GitHub Pages is enabled; left off rather
  than left failing.
