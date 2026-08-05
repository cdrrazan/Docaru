# The RenewalRule schema

Canonical contract: [`schema/renewal-rule.schema.json`](schema/renewal-rule.schema.json) (JSON Schema 2020-12).
Rules are written as YAML, one file per country × document kind, at `rules/<country>/<document_kind>.yml`.

This page explains what the fields *mean* and why some of them exist. The schema file is the authority on
what validates; this page is the authority on intent.

---

## The one idea the schema exists to encode

A deadline product is only worth anything if it answers **"when do I start?"** — not "when does it expire?".
Everything structural here serves that one derived number:

```
start_by = expires_on
         − processing.worst_case
         − max(obtain_lead_days of every required document)
         − buffer_days
```

Three deliberate choices follow from it.

**Reminders anchor on `worst_case`, never `typical`.** A reminder computed from the median case is correct
for the median applicant and useless for everyone in the tail — who are precisely the people a missed visa
deadline destroys. `processing_days_*` is therefore an object, not the scalar the original spec sketched.

**Prerequisites carry their own lead time.** `obtain_lead_days` on a required document is what turns
"renew by March" into "start in November". A police certificate that itself takes six weeks is not a
checklist item; it is six weeks of the plan. Without this field the computed date is confidently wrong.

**The rule can be infeasible, and we detect it.** If `window_opens_days_before` is smaller than the total
lead time, there is *no* legal date on which you can start and still finish before expiry. That is a real
situation, and it must surface as a warning telling the reader to plan around a gap rather than as a
silently impossible date. `bin/validate` reports it rather than rejecting the rule — the data is correct,
the process is the problem — and the generated page leads with it.

---

## Field notes

### Identity

| Field | Notes |
|---|---|
| `country_code` | The country whose authority **issues** the document — not where the holder lives. A Nepali passport is `NP` whether renewed in Kathmandu or London. |
| `document_kind` | A closed enum. Adding a kind is a deliberate one-line schema PR, because the consuming app needs UI for every kind that exists. |
| `title` | What the issuing country calls it, in English. Becomes the playbook heading. |

### The window

`window_opens_days_before` and `window_closes_days_before` are both counted **backwards from expiry**, so
"opens" is the larger number. Nepal permits passport renewal only once validity drops under a year:
`window_opens_days_before: 365`.

`window_closes_days_before` may be **negative**, meaning a grace period *after* expiry during which the
process is still a renewal rather than a fresh application. Where no such grace exists, use `0`.

### Cost

`amount` is the official fee for the standard service only — no couriers, no agents, no travel. Where a
fast-track exists, `expedited_amount`. Anything conditional (page count, age band, "cash in USD only")
goes in `note`, because those conditions are where people get turned away at the counter.

### Provenance, and why `status` is not cosmetic

Wrong renewal information is worse than none: it replaces a vague worry that prompts checking with a
false precision that prevents it. So provenance is structural, not a footnote.

- `status: draft` — numbers unconfirmed. Every surface that renders the rule **must** show a warning.
  The generated playbook page does.
- `status: verified` — a human opened the authority's own page and checked. The schema *requires*
  `verified_on` and `verified_by` in this state, so a wrong number always has a date and an owner.
- `source_urls` — at least one, always, even for drafts. `bin/validate` additionally requires a
  recognisably official source (`.gov`, `.gov.<cc>`, `.gob.`, `.govt.`, or a known mission domain)
  before it will accept `verified`.

Verification decays. `bin/validate --max-age-days N` fails rules verified longer ago than `N`;
CI runs it at 365 days, which is the discipline §13 of the spec calls for expressed as a build failure.

### `abroad_overrides`

Keyed by the country the applicant is applying **from**. This is the field that handles the case no
competitor does: two or three jurisdictions in parallel.

A Nepali passport renewed from London and from Doha share a legal window and a fee schedule, but not a
queue, not a mission, and not a set of local proof-of-residence demands. An override supplies only what
differs; every unstated field falls back to the top level. Each override carries its own `status` and
`source_urls`, so a well-verified base rule cannot launder an unverified branch.

Every `(document, from-country)` pair renders as its own playbook page — which is also the SEO unit.
Five Nepali documents with four origins each is 25 pages from 5 files.

---

## Deviations from the original spec sketch

The product spec's §6 sketched `RenewalRule` with scalar `processing_days_domestic` / `processing_days_abroad`
and no provenance state. Four changes, each earning its complexity:

1. **`processing_days_*` became `{typical, worst_case}`** — reminders need the tail, per above.
2. **`abroad_overrides` added** — per-mission variation is the wedge; a single `processing_days_abroad`
   scalar cannot express it.
3. **`status` + validator-enforced official sourcing added** — the liability question the spec left open
   in §12 Q4, answered structurally rather than with a disclaimer.
4. **`obtain_lead_days` added to requirements** — without it the start-by date ignores prerequisite chains,
   which is the exact failure the product exists to fix.

`schema_version` is `1`. Breaking changes bump it; additive optional fields do not.
