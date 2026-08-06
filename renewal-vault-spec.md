# Renewal Vault — product spec v0.1

**Name:** Docaru. The §12 question is settled: the application is the vault, so the name roots on
the documents rather than on the renewals, which are the layer above. The public renewal-rule dataset
keeps the `Renewaru` module — that name was only ever wrong for the application.

---

## 1. Positioning

> **Every document you own has a deadline. We tell you which one is next, and exactly what to do about it.**

Not a storage product. A **deadline product** that happens to store documents so it can be accurate about the deadlines.

This distinction governs every decision below. If the pitch drifts toward "keep your documents safe in one place," we have become a worse Google Drive and we lose.

---

## 2. Problem

Every adult carries 15–30 dated obligations: passport, visa, residence permit, driver's licence, vehicle registration, insurance policies, professional licences, tenancy agreements, appliance warranties, domain names, subscriptions.

They are scattered across email, drawers, and photos. The current solution is a badly-maintained calendar reminder, and it fails in a specific way: **the reminder fires too late.** A calendar entry says "passport expires March 14." It does not say "start in November, because renewing from abroad takes fourteen weeks and requires a police report you don't have yet."

The failure is not memory. It is **lead time and process ignorance.**

---

## 3. Who it's for

### Launch wedge: people living outside their home country

Migrants, work-visa holders, international students, expat families, diaspora managing parents' documents back home.

Why this wedge:

| Factor | Why it matters here |
|---|---|
| Consequence | A missed warranty costs $200. A missed visa costs legal status, job, re-entry rights. |
| Complexity | Two or three jurisdictions running in parallel — no existing product handles this |
| Reachability | Concentrated in immigration subreddits, country-specific expat groups, relocation forums. Reachable with zero ad budget. |
| Willingness to pay | Already spending thousands on lawyers and filing fees |
| Founder fit | Rajan is entering this situation personally within 12 months |

### Expansion path

Cross-border individuals → their households → general household documents (warranties, insurance, vehicles) → small business compliance.

**Do not start general.** Every competitor is general. General is where you are one of six identical products.

---

## 4. What it actually is — three layers

### Layer 1 — Renewal rules (the moat)

A public, versioned, open dataset. Per country × document type:

- Legal renewal window (earliest and latest you may apply)
- Realistic processing time, split by domestic vs. from abroad
- Required supporting documents
- Cost
- Where to apply, with links
- Consequences of lapsing
- Last verified date and by whom

This is a research grind, not an engineering problem — which is exactly why funded single-country competitors won't do it.

### Layer 2 — Alerts (the retention engine)

Lead time is **computed from the rule**, not chosen by the user. Cascading notifications anchored to "start by" rather than "expires on."

Notifications are the product. Retention does not depend on the user remembering to open anything.

### Layer 3 — Vault (the accuracy substrate)

Documents stored so that expiry dates are captured automatically rather than typed. Storage exists to remove data-entry friction — the historical killer of every personal records product.

---

## 5. Competitive position

| Product | Scope | Hosted | Open | Multi-country | Renewal process |
|---|---|---|---|---|---|
| DocStow | General household | Yes | No | No (NZ) | No |
| NeuVault | General docs | Yes | No | No | No |
| DigiVault | Encrypted vault | Yes | No | No | No |
| Travel Document Vault | Travel only | Offline | No | Partial | No |
| Warracker | Warranties only | Self-host | Yes | N/A | No |
| Expiration Reminder | B2B compliance | Yes | No | No | No |
| **This** | **General** | **Yes** | **Yes** | **Yes** | **Yes** |

Two cells are unoccupied by anyone: **open + hosted**, and **renewal process knowledge**. Those are the product.

---

## 6. Data model

Two data planes with opposite properties. Keep them physically separate.

### Private plane (per user, minimal, encrypted)

```
Household
  └── Member (person a document belongs to)
        └── Document
              - kind (passport, visa, warranty, ...)
              - issuing_country
              - issued_on, expires_on
              - identifier (encrypted)
              - notes (encrypted)
              └── Attachment
                    - blob (encrypted client-side)
                    - page_no, content_type
```

### Public plane (shared, open, versioned)

```
RenewalRule
  - country_code
  - document_kind
  - window_opens_days_before
  - window_closes_days_before
  - processing_days_domestic
  - processing_days_abroad
  - required_documents[]
  - cost { amount, currency }
  - authority_url
  - lapse_consequence
  - verified_on, verified_by
  - source_urls[]
```

Ships as YAML in a public git repo, consumed by the app. Contributors open a PR against a file and never touch user data.

### Derived

```
Reminder = Document.expires_on
         − RenewalRule.processing_days(context)
         − buffer
```

---

## 7. Architecture decisions

**Encryption split.** Attachments encrypted client-side; extracted metadata (kind, country, expiry date) stored server-side in plaintext. The server can compute reminders and render dashboards but has never seen a passport scan. Decide this before the first migration — retrofitting is brutal.

**Capture.** Passport MRZ parsing on day one. The machine-readable zone is deterministic to parse (unlike general OCR) and turns onboarding into pointing a camera. Cold start is the primary product risk; this is the primary mitigation.

**Storage.** Downscale to ~1600px, WebP, target 200–400KB per page. Free tier capped by **document count** (15–20), not megabytes. Families hitting the cap is the upgrade trigger.

**Self-hosting.** Ship a single-container Docker image. It is a **credibility signal**, not a distribution channel — target users do not run Docker. Do not over-invest.

**Stack.** Rails 8, PostgreSQL, Hotwire, Solid Queue for the reminder scheduler, Kamal, Cloudflare. PWA before native apps.

---

## 8. Pricing

| Tier | Price | Contents |
|---|---|---|
| Free | $0 | 1 person, 20 documents, all alerts, all renewal playbooks |
| Household | ~$4/mo or $36/yr | Unlimited documents, up to 6 members, shared alerts, priority notification channels |
| Self-hosted | $0 | Full features, own infrastructure |

Alerts and playbooks are **never** paywalled. Paywalling the safety feature poisons the trust position that the whole product rests on, and trust is what open source buys us.

---

## 9. Distribution

The bottleneck is not engineering. It is sustained content output — which is the part most engineers fail at and where Rajan already has a track record.

**Every renewal playbook is simultaneously a product feature and a page that ranks.**

"How long does Nepali passport renewal take from the UK" is a real query with real volume and almost no competition. Written once, it acquires users indefinitely and feeds the alert engine.

Channels in priority order:

1. Playbook pages (organic search — the compounding channel)
2. Country-specific expat and immigration communities
3. GitHub / Hacker News for the open source angle
4. Existing digitonX newsletter and audience

**Lesson from Trackaru: the marketing site must be server-rendered.** A client-side SPA is invisible to crawlers, which kills the only channel that compounds.

---

## 10. Build phases and gates

Each gate must be met before starting the next phase. No exceptions — the failure mode this guards against is building storage first because it is the most satisfying to build.

### Phase 0 — Rules dataset
Public repo. 3 countries × 5 document types = 15 playbooks. No app at all.
**Gate:** 15 playbooks published, and either 3 external contributions or 500 organic visits/month.

### Phase 1 — Anonymous calculator
Single page, no account. "When should I start renewing X?" → date + steps + cost.
**Gate:** 200 uses/month sustained for two months.

### Phase 2 — Accounts and alerts, no file storage
Users type a document kind, country, and expiry date. Email and push reminders.
**Gate:** 100 users with 3+ documents, and 40% still active at day 60.

### Phase 3 — Vault
Encrypted attachments, MRZ capture, household sharing. Paid tier launches here.
**Gate:** 3% free-to-paid conversion.

### Phase 4 — Consolidation
Self-host image. Evaluate merging Trackaru as the recurring-payments module.

---

## 11. Kill criteria

Named in advance so they can't be rationalised away later.

- **Phase 0 produces zero external contributions in 6 months.** The community moat is imaginary; the whole differentiation collapses to a solo research burden. Stop.
- **Phase 2 day-60 retention below 20%.** The notification hook isn't strong enough. No amount of storage polish fixes this.
- **A funded competitor ships multi-country renewal rules first.** Reassess — the wedge is gone.
- **Under 5 hours/week available for 8 consecutive weeks.** This needs 12 months of consistent content to compound. Half-committed produces nothing; better to stop cleanly.

---

## 12. Open questions

1. **Naming.** The `-ARU` convention is a portfolio signal that means nothing to a migrant family in Berlin. This product needs a consumer name that says "deadline," not "vault."
2. **First country pair.** Nepal-outbound (verifiable, community access, personal knowledge) vs. a large destination market (bigger volume, harder to verify). Recommend Nepal-outbound for accuracy.
3. **Trackaru merge timing** — Phase 4, or never? Depends on Trackaru's current user base.
4. **Liability framing.** Wrong renewal information is worse than none. Needs visible last-verified dates, explicit "confirm with the authority" language, and a correction path.

---

## 13. Honest risks

- **Cold start.** Worthless until ~15 documents are in. MRZ capture mitigates but does not eliminate this.
- **Dead time.** Nobody opens a document vault for months. The product must be entirely notification-driven; email deliverability and push reliability are core infrastructure, not polish.
- **Stale rules.** Government processes change. Requires ongoing verification discipline forever.
- **Crowding.** Four closed competitors launched in roughly the last 12 months. The niche is validated and the window is not indefinite.
