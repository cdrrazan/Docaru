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
- Reminder cascade anchored to the start date rather than the expiry date, swept nightly.
- Prerequisite chains: warns when one document's lapse will block another's renewal.
- MRZ reader for passports and ID cards, with check-digit validation.
- Vault: attachments encrypted in the browser; the server holds only ciphertext.
- Self-hosted image via Docker Compose: the application plus a MySQL server.

### Known gaps

- No renewal rule has been verified. Every playbook says so.
- No payment processor; the upgrade button switches plans without charging.
- The Docker image has never been built — this was developed without a Docker daemon available.
  The application itself has been exercised against a real MySQL server; the image around it has not.
- MRZ capture is paste-only; no camera yet.
- Push notifications are not implemented. Email only.
