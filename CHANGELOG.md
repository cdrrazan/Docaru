# Changelog

Notable changes, newest first. Rule data corrections are not listed individually —
`git log rules/` is the authority on those, and each rule carries its own `verified_on`.

## Unreleased

Everything so far. Nothing is released yet, and the dataset is entirely unverified.

### The dataset

- `RenewalRule` schema with renewal windows, split processing times, prerequisite lead times, cost,
  provenance, and per-origin overrides.
- Five Nepali documents — passport, police clearance, driving licence, vehicle registration,
  third-party motor insurance — with overrides for GB, US, AU and QA. 21 playbooks.
- `bin/validate`: schema conformance, internal consistency, provenance quality, verification
  staleness at 365 days, feasibility, and dependency-graph soundness.
- `bin/build`: static playbook site and a machine-readable bundle.
- Everything ships as `status: draft`. No figure has been confirmed against an issuing authority.

### The application

- Renewal playbooks served at readable URLs, server-rendered, no account.
- Anonymous start-date calculator; the question lives in the URL so answers can be shared.
- Accounts, households, members, documents.
- Reminder cascade anchored to the start date rather than the expiry date, swept nightly, delivered
  by email and — where a household has enabled it — by web push. No billing state ever stops one.
- Prerequisite chains: warns when one document's lapse will block another's renewal.
- MRZ reader for passports and ID cards, with check-digit validation, read from a camera or pasted.
- Vault: attachments encrypted in the browser; the server holds only ciphertext.
- Installable as a PWA, with the public playbooks readable offline.
- Web push alongside email, and billing through Paddle.
- Self-hosted image via Docker Compose: the application plus a MySQL server.
- A seeded demo household covering every state the dashboard can reach.

### Fixed before first release

- **A playbook could give a wrong answer.** `/playbooks/np/passport/from-np` rendered "renewal from
  Nepal" against the *abroad* processing times — months of lead time too many for somebody standing
  in Kathmandu. It now redirects to the domestic playbook.
- **The domestic page existed at 676 addresses per document.** Any two letters matched the origin
  segment and unknown ones silently fell back to the domestic view, so crawlers were asked to work
  out which of them was real. An origin that is not a country is now a 404; a country with no
  override still renders on the generic abroad timings, which was always the intent.
- **The calculator told visitors off before they had done anything.** `applying_from` defaulted to
  `"domestic"`, so the parameter hash was never blank and every arrival counted as a submission —
  the first thing anybody saw on the top of the funnel was a validation error listing three fields
  they had not reached.
- **A camera misread is now repaired rather than rejected**, but only where the check digits agree:
  digit-shaped letters are mapped to digits inside the runs the standard defines as numeric, and any
  repair the checksums reject is discarded. A single deterministic candidate, not a search — trying
  substitutions until one satisfies a one-digit checksum would find a passing answer roughly one time
  in ten whether or not it was true.

### Known gaps

- No renewal rule has been verified. Every playbook says so, on every page.
- The dataset covers one issuing country. Breadth is a research grind, not an engineering problem.
- The Docker image has never been built — this was developed without a Docker daemon available.
  The application itself has been exercised against a real MySQL server; the image around it has not.
- The Paddle integration is tested against payloads built from the documented shapes, not against a
  live sandbox. Confirm the field names and the signature format with a real test event before
  taking money.
