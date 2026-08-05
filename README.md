# Renewal rules

**Every document you own has a deadline. This is the open dataset that says which one is next,
and exactly what to do about it.**

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

## Running the application

Needs MySQL 8.0+ or MariaDB 10.6+. Point it at a server with `DATABASE_HOST`, `DATABASE_USERNAME`
and `DATABASE_PASSWORD`, or take the defaults (`renewaru`/`renewaru` on `127.0.0.1`) and create the
user locally.

```sh
cd web
bin/setup
bin/rails server
```

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

## Caveat

Community-maintained reference information, not legal advice. Government processes change without
notice. Every page shows its last-verified date and links to the authority it came from — confirm
there before acting, and please [open a correction](CONTRIBUTING.md) when you find something wrong.

## Licence

Rule data (`rules/`) is [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) — use it, including
commercially, with attribution. Code (`lib/`, `bin/`, `test/`) is MIT. See [LICENSE](LICENSE).
