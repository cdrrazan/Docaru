# Changelog

Notable changes, newest first. Rule data corrections are not listed individually —
`git log rules/` is the authority on those, and each rule carries its own `verified_on`.

## Unreleased

Everything so far. Nothing is released yet, and the dataset is entirely unverified.

### A shopfront, a typeface, and an image that had never been built

**`marketing/`** — the static site at `docaru.com`, built with Astro and deployed to Cloudflare Pages,
with the application at `app.docaru.com`. It exists so copy can change without a Rails deploy. It is
static rather than a single-page app on purpose: organic search is the acquisition channel, the
playbook pages are the top of the funnel, and CI fails the build if a `<script>` tag or any
third-party host appears in the output.

It also replaced a homepage that was still selling the retired product. The old one opened "Every
document you own has a deadline", never mentioned the vault, encryption or self-hosting, and had no
link to pricing at all. The new one leads with the afternoon somebody loses to a document in a
cupboard in another country, and includes the row we lose in the comparison against cloud drives —
search inside documents is a real thing Drive does and we cannot, and saying so is what makes the
other rows credible. A related gap: the app's own navigation had no link to the vault.

**Google Sans**, self-hosted rather than linked from Google. Same OFL font, same files, but the CDN
version would send every reader's IP and referring page to Google on a page arguing that Google can
read your Drive and we cannot read your vault — and, since a 2022 Munich ruling, raise a live GDPR
question. See `marketing/FONTS.md`.

**The Docker image had never been built.** It has now, and it was broken twice:

- `assets:precompile` boots production inside a build layer, where the encryption initializer
  `fetch`ed three keys that cannot exist there. The build simply failed.
- **The dataset was invisible and nothing said so.** The library is copied to `/lib/docaru`, `/lib` on
  Debian is a symlink to `/usr/lib`, so `Docaru::ROOT` resolved to `/usr` and the rules were sought in
  `/usr/rules`. Zero rules loaded. The playbook index still returned 200 with an empty list and every
  playbook page 404'd — the entire public plane absent from every self-hosted instance, with no error
  anywhere. `DOCARU_RULES_DIR` existed for exactly this and was never set.

Prices are in USD and annual.

### A recovery code, and capacity priced on what it costs

Two things stood between this and being sellable as a hosted service, and neither was a missing
feature.

**Losing the passphrase meant losing the documents.** Defensible for software you run yourself,
close to unsellable hosted: the customer who forgets it loses everything, blames the operator, and
is right that nobody can help. Scans are now encrypted under a random vault key rather than under
the passphrase itself, and that key is stored twice — wrapped under the passphrase, wrapped under a
160-bit recovery code. Both wrappings are made in the browser, so the server still holds two blobs
and no key; an operator, a stolen backup and a subpoena all still get nothing. Lose both and the
files are still gone, which has not changed and should not. A side effect worth having: a wrong
passphrase is now caught at unlock, where previously it was discovered later as a gallery full of
failed decryptions.

**The free tier metered the wrong thing.** The pricing page claimed to limit storage; the code
limited document count, at 20 — while one document could hold 100 pages of 10 MB, putting the real
free ceiling near 20 GB. Bytes are metered now, where bytes arrive, and documents are unlimited on
every plan including free. Recording that a marriage certificate exists is the point of the vault,
and it costs a database row.

Also: plans are annual rather than monthly, because a vault is opened about three times a year and
monthly billing offers twelve chances a year to cancel it. A 100 GB Archive tier for decades of
scanned paper. One Paddle price per plan, with the old `PADDLE_PRICE_ID` still read as the household
price so a configured instance keeps working. And the pricing page now states the actual reason to
pay for hosting — that we cannot read the files and a cloud drive can read theirs — along with what
that rules out: no search inside documents, no previews, nothing that needs the plaintext.

Unchanged and now tested at every billing status: going over a limit costs capacity, never access.
Nothing is deleted, nothing stops being watched, and `alerting?` stays unconditionally true.

### The vault holds documents from anywhere

The country picker offered fourteen countries — the ones the renewal dataset happened to mention.
That was the right list for a renewal tracker and the wrong list for a vault: a Kenyan birth
certificate could not be filed, not because anything refused to store it, but because the dropdown
had no Kenya in it. `Docaru::Countries` is now the whole of ISO 3166-1, 249 entries, with alpha-3
alongside so the passport reader can use the same table.

The reason it stayed at fourteen for so long is that one list was doing two jobs. It named countries
*and* it decided which playbook URLs were real, so widening it would have widened the crawl surface
to every country times every rule — the duplicate-content problem that was already fixed once. Those
are separate now: `Countries::ISO` names, `Rule#origins` decides. An origin with an override is a
distinct answer and stays indexable; an origin without one still renders the generic abroad timings,
because somebody asked and the timings are honest, but carries `noindex`.

Also: the passport reader maps every ISO country rather than the fourteen, plus the ICAO codes that
are not ISO codes — `D` for Germany, and the `GB*` family for the classes of British nationality.
Codes that name no country at all (`XXA` and the other stateless and refugee documents, the UN
codes) still return nil, so the field stays empty for a person to complete rather than being filled
with a guess.

Adding a country to the *renewal* side is still one YAML file and no application change.

### Renamed to Docaru

The application was called Renewaru, which named the layer on top rather than the thing underneath —
the same inversion the repositioning below corrected in the code. The vault is the product, so the
name roots on the documents.

**One name, including the dataset.** The first pass kept `Renewaru` as the dataset's Ruby namespace,
on the grounds that it was accurate for a renewal-rule dataset even once it was wrong for the vault.
That was a distinction worth less than it cost: the two planes are a directory boundary, not a
distribution one — no separate repository, no gem — so the second name only asked every contributor
to work out which was which, and left a retired brand sitting in live code. `lib/renewaru/` is now
`lib/docaru/`, the module is `Docaru`, and `RENEWARU_RULES_DIR` is `DOCARU_RULES_DIR`.

Not a no-op for anyone already running it:

- Default database names move from `renewaru_*` to `docaru_*` and the default user from `renewaru` to
  `docaru`. Either grant the new user (`web/README.md` has the statement) or set `DATABASE_NAME` and
  `DATABASE_USERNAME` to the old values — nothing in the schema changed, only what it is called.
- The Compose volumes are renamed, which **orphans** the old ones rather than deleting them. A
  `docker compose up` after this starts against empty storage until `renewaru-db` and
  `renewaru-storage` are renamed to `docaru-db` and `docaru-storage`. Nothing is destroyed, but the
  encrypted attachments are not reachable until the volumes match, and they cannot be recovered from
  anywhere else.
- The schema's `$id` moves to the new repository URL, changing the identity of the schema document.
  Safe now because nothing external consumes it; it would not have been later.

### Repositioned: the vault is the product

The application began as a renewal-deadline tracker that happened to store documents. It is now an
encrypted, self-hosted document vault that happens to know about renewal deadlines. The difference is
not cosmetic — it changed what the software will accept:

- **`expires_on` is optional.** It was required, which meant a degree certificate, a birth
  certificate, a marriage certificate, a transcript and a property deed were all literally
  unstorable. That is most of what a household keeps, and all of what somebody needs at short notice
  from the wrong city. A document without an expiry is `:stored` — a finished state, distinct from
  `:unknown`, which means it *does* expire and no rule exists for it.
- **Document kinds are open.** The dataset's enum stays closed so the app never meets a kind it has
  no renewal UI for, but refusing to store a transcript because nobody has written a renewal rule for
  transcripts was the tail wagging the dog.
- **There is a vault to browse.** Previously there was no document index at all — the dashboard was
  the list, ranked by urgency. That is the right shape for a deadline tracker and useless for finding
  one certificate, which is the actual daily use. Search covers label, kind, country and person, and
  deliberately not the encrypted fields.
- **The dashboard has two zones.** "Needs you" holds only documents that can want something; a vault
  is mostly documents that want nothing, and listing a birth certificate under "needs attention"
  would teach people to skim past the part that matters.

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
- Nobody has run this in production, including its author. The image builds and runs on a laptop;
  that is not the same as having operated it.
- The Paddle integration is tested against payloads built from the documented shapes, not against a
  live sandbox. Confirm the field names and the signature format with a real test event before
  taking money.
