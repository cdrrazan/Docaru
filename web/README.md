# The application

The Rails 8 app that consumes the renewal dataset in the repository root. The dataset is the public
artefact and lives at the top; this reads it. See [`../README.md`](../README.md) for what the project
is, and [`../CLAUDE.md`](../CLAUDE.md) for the architecture in full.

## Running it

Needs Ruby 3.3 and MySQL 8.0+ or MariaDB 10.6+.

```sh
bin/setup                  # bundle, create the database, start the server
bin/rails db:seed          # a demo household — see below
```

Defaults to `docaru`/`docaru` on `127.0.0.1`. Override with `DATABASE_HOST`, `DATABASE_USERNAME`
and `DATABASE_PASSWORD`. If the user does not exist yet:

```sql
CREATE USER 'docaru'@'localhost' IDENTIFIED BY 'docaru';
GRANT ALL PRIVILEGES ON `docaru\_%`.* TO 'docaru'@'localhost';
```

The wildcard matters. The app uses four databases — its own plus separate ones for Solid Cache, Queue
and Cable — and the test suite creates a set per parallel worker.

## The demo

`bin/rails db:seed` builds a household holding every state the dashboard can reach, because an empty
dashboard demonstrates nothing:

Six of the thirteen never expire — which is roughly what a real drawer looks like, and the reason the
vault exists:

| Document | State |
|---|---|
| Citizenship certificate, degree, transcript | **stored** — no expiry, no reminders |
| Birth certificate, marriage certificate | **stored** |
| Land deed (*lalpurja*) | **stored** |
| Passport, from the UK | on track |
| Passport, from the UK | start now |
| Police clearance, from the UK | **overdue** — the day to start was a month ago |
| Driving licence | **impossible** — the process is longer than the window is open |
| Third-party insurance | **expired** |
| Vehicle registration | **blocked** by the expired insurance above |
| UK residence permit | no rule in the dataset yet |

Sign in as `demo@docaru.test` / `demo-password-change-me`. Seeds run only in development and test,
are idempotent, and are dated relative to today so they never go stale.

The stored rows are the product: documents somebody needs at short notice and cannot reach. The last
two are what the renewal layer adds — Nepal will not renew a vehicle registration without current
insurance, both dates look survivable in isolation, and the renewal is blocked before it starts.

## Tests

Minitest with fixtures, Rails default. **Not RSpec** — do not introduce it here.

```sh
bin/rails test                                    # everything
bin/rails test test/models/document_test.rb       # one file
bin/rails test test/models/document_test.rb:42    # one test
bin/ci                                            # tests, RuboCop, Brakeman, audits, seeds
```

Tests run in parallel and each worker needs its own four databases, so the test user needs create
rights. CI uses `root` for that reason.

## Optional services

All of it is optional. Without any of it the app runs, renders every page, and sends every reminder
by email — the features simply do not appear. See [`../.env.example`](../.env.example).

| | Without it |
|---|---|
| SMTP | No reminders are delivered, which is the one thing this exists to do. Configure it first. |
| `VAPID_*` | No push notifications, and the toggle is hidden. Email still goes out. |
| `PADDLE_*` | No checkout; every household stays free. Alerts and playbooks are never paywalled regardless. |

Generate the push keys once and keep them — rotating invalidates every subscription your users have
already granted, and browsers will not prompt again:

```sh
bin/rails runner 'k = WebPush.generate_key; puts k.public_key; puts k.private_key'
```

`PADDLE_ENVIRONMENT` defaults to `sandbox`. Of the two ways to get that wrong, the one that cannot
charge anybody is the better default.

## Worth knowing before editing

- `app/models/rule_catalog.rb` — the only bridge to the dataset. Nothing else reads `rules/`.
- `app/models/reminder_schedule.rb` — derived on every sweep, never stored, so correcting an expiry
  date reshapes every future alert with no backfill.
- `app/jobs/deliver_reminders_job.rb` — the nightly sweep. This job is the product.
- `app/javascript/controllers/vault_controller.js` — browser-side AES-GCM. The server holds
  ciphertext and no key; never add server-side decryption.
- `app/views/pwa/service-worker.js` — caches public playbooks by allowlist, never anything behind
  authentication.
