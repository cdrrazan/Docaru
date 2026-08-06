# Renewal rules

**Every document you own has a deadline. This is the open dataset that says which one is next,
and exactly what to do about it — plus the application that watches yours.**

[![Validate rules](https://github.com/cdrrazan/Renewaru/actions/workflows/validate.yml/badge.svg)](https://github.com/cdrrazan/Renewaru/actions/workflows/validate.yml)
[![App](https://github.com/cdrrazan/Renewaru/actions/workflows/app.yml/badge.svg)](https://github.com/cdrrazan/Renewaru/actions/workflows/app.yml)
[![Data: CC BY 4.0](https://img.shields.io/badge/data-CC%20BY%204.0-blue)](LICENSE)
[![Code: MIT](https://img.shields.io/badge/code-MIT-blue)](LICENSE)

A calendar reminder tells you a passport expires on 14 March. It does not tell you to start in
November, because renewing from abroad takes ten weeks and needs a police certificate you have not
ordered yet. The failure is not memory — it is **lead time and process ignorance**, and that is
what this data fixes.

Per country × document type, versioned in public:

- the legal renewal window — the earliest and latest you may apply
- realistic processing time, split by whether you are applying at home or from abroad, and **from where**
- required supporting documents, each with its own lead time
- cost, the authority to apply to, and what happens if you let it lapse
- when it was last verified, by whom, and against which source

---

## Status

| | |
|---|---|
| Rules | 5 documents, 1 issuing country (Nepal) |
| Playbook pages | 21 |
| Verified | 0 — **everything here is currently `draft`** |

The figures are structured, sourced, and internally consistent. They are **not yet confirmed
against the issuing authorities**, and every page that renders them says so prominently. Verifying
them is the most valuable contribution available; see [CONTRIBUTING.md](CONTRIBUTING.md).

## Layout

```
rules/     the public dataset — YAML, one file per country x document
schema/    the RenewalRule contract
lib/       the loader, timeline arithmetic, and validator (no gems, no network)
bin/       validate and build
web/       the Rails 8 application, which consumes the above
```

`rules/` sits at the top because it is the public artefact. Somebody correcting a renewal date
should never have to learn that the application exists.

## Using the dataset

```sh
ruby bin/validate          # check every rule
ruby bin/build             # generate the static playbook site into site/
ruby test/schema_test.rb
```

Ruby 3.x, no gems, no bundler, no network. That is a deliberate constraint: a dataset that needs a
toolchain installed before you can fix a typo in it gets fewer corrections.

`bin/build` also emits `site/rules.json` — the whole dataset plus the derived timeline for each
playbook, so a consumer never has to reimplement the arithmetic.

[`examples/`](examples/) has runnable consumers in Ruby, Python, JavaScript and jq. All four answer
the same question and print the same date, which is the point: the published bundle is enough on its
own, and the derived number does not depend on who derives it.

## Seeing it work

Needs Ruby 3.3 and MySQL 8.0+ or MariaDB 10.6+.

```sh
cd web
bin/setup --skip-server
bin/rails db:seed          # a household with something wrong in it
bin/rails server
```

Sign in at `/session/new` as `demo@renewaru.test` / `demo-password-change-me`.

The seeded household holds every state the dashboard can reach — on track, due now, overdue,
impossible, expired, and a document the dataset has no rule for. Two rows are the ones to look at:

> **Third-party insurance** — expired a fortnight ago
> **Vehicle registration** — due to be renewed in two months, and **blocked**, because Nepal will not
> renew one without the other

Both dates look survivable on their own. The renewal is already blocked. That is the failure a
product storing only expiry dates cannot see, and it is the reason this one stores renewal *process*
rather than renewal dates.

Defaults to `renewaru`/`renewaru` on `127.0.0.1`; override with `DATABASE_HOST`, `DATABASE_USERNAME`
and `DATABASE_PASSWORD`. Full setup notes, including the database grant, are in
[`web/README.md`](web/README.md).

Or self-host:

```sh
cp .env.example .env && $EDITOR .env    # generate the secrets
docker compose up -d --build
```

Two containers: the application and MySQL. The application is still a single process — Solid Queue
runs inside Puma, so the nightly reminder sweep is not a separate service anyone can forget to
start. That sweep is the product.

Back up **both** volumes. `renewaru-db` holds the deadlines; `renewaru-storage` holds the encrypted
attachments. Neither is much use without the other.
(Caveat: the image has not yet been built — see [CHANGELOG.md](CHANGELOG.md).)

## What the application does

- **Playbooks** — every rule rendered per origin, server-rendered, no account needed.
- **A start-date calculator** — anonymous, nothing stored, the question in the URL so answers can be
  shared into a forum thread.
- **Reminders anchored to the start date**, not the expiry date, cascading before and after it.
- **Prerequisite chains** — warns when one document lapsing will block another's renewal. Nepal will
  not renew a vehicle registration without current insurance; both dates look fine in isolation.
- **MRZ reading** — passports and ID cards, with check-digit validation, so a misread is caught
  rather than stored as somebody's expiry date.
- **A vault** — scans encrypted in the browser. The server holds ciphertext and no key.
- **Installable, and readable offline** — the playbooks are cached for a queue at a consulate or a
  plane. Only the public ones: nothing behind a login is ever written to disk.

Reminders arrive by email always, and by web push where a household has turned it on. **No billing
state ever stops one.** Somebody whose card expires while they are abroad is precisely the person
most likely to need the alert, so a lapsed subscription costs capacity — more people, more documents
— and never safety. There is a test that walks every billing status and asserts it.

## How a rule works

```yaml
country_code: NP                  # who issues it, not where you live
document_kind: passport
window_opens_days_before: 365     # Nepal will not accept an application earlier
processing_days_abroad:
  typical: 42
  worst_case: 75                  # what the plan is built on
required_documents:
  - item: Nepali citizenship certificate
    obtain_lead_days: 90          # a prerequisite is lead time, not a checklist item
abroad_overrides:
  QA:                             # renewing from Doha is not renewing from London
    processing_days: { typical: 40, worst_case: 75 }
    additional_documents:
      - item: Qatar ID (QID)
```

Which produces the only number that matters:

```
start_by = expires_on − worst_case − slowest prerequisite − buffer
```

Full field reference and design rationale: [SCHEMA.md](SCHEMA.md).

## What the validator checks

Beyond schema conformance, `bin/validate` enforces the things that make the data trustworthy:

- **Provenance.** A rule cannot claim `verified` without an official government source, a date, and
  a named human. An override cannot inherit trust from a verified parent it does not share.
- **Staleness.** Verification older than a year fails the build. Government processes change, so a
  figure nobody has re-read in twelve months is not verified, it is old.
- **Consistency.** The window must run in the right direction, worst case must exceed typical, and
  a file's location must match its contents.
- **Feasibility.** Where the total lead time exceeds the renewal window, the process *cannot be
  completed before expiry*, however well you plan. That is reported rather than rejected — it is a
  fact about the world, and the fact a reader most needs. Nine of the current 21 playbooks are in
  this state, including renewing a Nepali bluebook from the US and renewing a Nepali driving licence
  from anywhere at all.

## Two data planes

The split is structural, not a convention.

**Public plane** — `rules/`. Open, versioned, edited by pull request. Contains no user data, so a
contributor correcting a fee comes nowhere near anybody's passport.

**Private plane** — the application's database. Document metadata (kind, country, expiry) is stored
in the clear because the server must compute start-by dates and cannot do that over ciphertext.
Identifiers and notes are encrypted at rest. Attachments are encrypted in the browser, and the
server has no key. [SECURITY.md](SECURITY.md) is precise about what that does and does not protect.

Alerts and playbooks are never paywalled. Paywalling the safety feature would poison the trust the
whole thing rests on.

## Helping

The most valuable contribution is not a new country. **It is verifying one that already exists.**
Every rule here says `draft`, meaning the numbers are estimates nobody has checked against the
issuing authority — and a wrong renewal date is worse than none, because it replaces a vague worry
that prompts checking with a false precision that prevents it.

Turning one draft into a sourced `verified` is worth more than five new drafts. It takes an evening
and a government website. [Claim one first](../../issues/new?template=verify-a-rule.md) so two people
do not read the same consulate page, then see [CONTRIBUTING.md](CONTRIBUTING.md) for the bar.

Correcting a rule needs no toolchain: edit one YAML file, run `ruby bin/validate`, open a pull
request. No bundler, no database, no account.

## Caveat

Community-maintained reference information, not legal advice. Government processes change without
notice. Every page shows its last-verified date and links to the authority it came from — confirm
there before acting, and please [open a correction](CONTRIBUTING.md) when you find something wrong.

## Licence

Rule data (`rules/`) is [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) — use it, including
commercially, with attribution. Code (`lib/`, `bin/`, `test/`) is MIT. See [LICENSE](LICENSE).
