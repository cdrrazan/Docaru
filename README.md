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

Phase 0 of [the product spec](#relationship-to-the-product): the dataset, no application.

| | |
|---|---|
| Rules | 5 documents, 1 issuing country (Nepal) |
| Playbook pages | 21 |
| Verified | 0 — **everything here is currently `draft`** |

The figures are structured, sourced, and internally consistent. They are **not yet confirmed
against the issuing authorities**, and every generated page says so prominently. Verifying them is
the most valuable contribution available; see [CONTRIBUTING.md](CONTRIBUTING.md).

## Using it

```sh
ruby bin/validate    # check every rule
ruby bin/build       # generate the playbook site into site/
ruby test/schema_test.rb
```

Ruby 3.x, no gems, no bundler, no network. That is a deliberate constraint: a dataset that needs a
toolchain installed before you can fix a typo in it gets fewer corrections.

`bin/build` also emits `site/rules.json` — the whole dataset plus the derived timeline for each
playbook, which is what an application consumes rather than reimplementing the arithmetic.

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

## Relationship to the product

This repository is the public plane — open, shared, and versioned. It contains no user data and is
designed so that a contributor never touches any.

The private plane (documents, expiry dates, attachments) lives in the application and is separate by
construction: attachments encrypted client-side, only extracted metadata server-side. A contributor
here opens a pull request against a YAML file and comes nowhere near a user's passport scan.

Alerts and playbooks are never paywalled. Paywalling the safety feature would poison the trust the
whole thing rests on.

## Caveat

Community-maintained reference information, not legal advice. Government processes change without
notice. Every page shows its last-verified date and links to the authority it came from — confirm
there before acting, and please [open a correction](CONTRIBUTING.md) when you find something wrong.

## Licence

Rule data (`rules/`) is [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) — use it, including
commercially, with attribution. Code (`lib/`, `bin/`, `test/`) is MIT. See [LICENSE](LICENSE).
