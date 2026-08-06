# Using the dataset

Four runnable examples of consuming the renewal rules from outside this repository. The data is
[CC BY 4.0](../LICENSE) — use it commercially, with attribution.

All four answer the same question, and all four give the same answer:

> A Nepali passport expiring **14 March 2027**, renewed from the UK.
> **Start by 14 September 2026** — 181 days before it expires.

| | Reads | Run it |
|---|---|---|
| [`ruby/start_date.rb`](ruby/start_date.rb) | `rules/` directly | `ruby examples/ruby/start_date.rb NP passport GB 2027-03-14` |
| [`python/start_date.py`](python/start_date.py) | `site/rules.json` | `python3 examples/python/start_date.py NP passport GB 2027-03-14` |
| [`javascript/start-date.mjs`](javascript/start-date.mjs) | `site/rules.json` | `node examples/javascript/start-date.mjs NP passport GB 2027-03-14` |
| [`shell/queries.sh`](shell/queries.sh) | `site/rules.json` | `examples/shell/queries.sh` |

The three that read `site/rules.json` need it built first. It is generated, not committed, so it can
never drift from the rules it claims to render:

```sh
ruby bin/build          # writes site/rules.json and the static playbook pages
```

The Ruby example needs nothing built — it loads `rules/` through the library, so a rule you edited a
second ago is a rule it sees.

## The one thing to copy

**Do not recompute the arithmetic.** `start_days_before_expiry` is already in the bundle, worked out
from the worst-case processing time, the slowest prerequisite and the buffer. Subtract it from the
expiry date and stop:

```
start_by = expires_on − timeline.start_days_before_expiry
```

Reimplementing that in each consumer is how five tools end up disagreeing about one passport — and
four of them will be wrong in the direction that costs somebody a visa.

## Three things that will surprise you

**`feasible: false` is not an error.** For some documents the process takes longer than the renewal
window is open, so there is *no* legal date on which you can start and still finish before expiry.
That is a true fact about the bureaucracy, not a defect in the data, and it is the fact a reader most
needs. Surface it; do not filter it out. Nine of the current twenty-one playbooks are in this state.

**Plan on `worst_case_days`, never `typical_days`.** A date derived from the median is correct for
the median applicant and useless for everyone in the tail — and the tail is where a missed deadline
costs somebody their job or their legal status. The gap is not academic: a Nepali driving licence is
30 days typical against 365 worst case.

**An unknown origin must not fall back to domestic.** Applying through a mission abroad is slower
than applying at home, sometimes by months. If you have no entry for the country somebody is applying
from, fall back to the *slowest* origin you do have — as the Python and JavaScript examples do.
Guessing has to err towards starting too early: the cost of that is waiting, and the cost of the
other is a lapsed document.

## Exit codes

Each example exits `0` when the renewal is feasible and `2` when it cannot be completed before
expiry, so they compose into a shell pipeline:

```sh
ruby examples/ruby/start_date.rb NP drivers-licence domestic 2027-01-01 || echo "plan for a gap"
```

## Status

Every figure in this dataset is currently `draft` — estimated, and not yet confirmed against the
issuing authority. Each example says so on every run, and anything built on this should too. See
[CONTRIBUTING.md](../CONTRIBUTING.md) if you would like to fix that; it is the most useful thing
anyone can do here.
