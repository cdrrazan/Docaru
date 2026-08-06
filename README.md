<div align="center">

# Renewaru

**A self-hosted vault for the documents you will not put in Google Drive —**
**that also tells you when the ones with deadlines need renewing.**

[![Validate rules](https://github.com/cdrrazan/Renewaru/actions/workflows/validate.yml/badge.svg)](https://github.com/cdrrazan/Renewaru/actions/workflows/validate.yml)
[![App](https://github.com/cdrrazan/Renewaru/actions/workflows/app.yml/badge.svg)](https://github.com/cdrrazan/Renewaru/actions/workflows/app.yml)
[![Data: CC BY 4.0](https://img.shields.io/badge/data-CC%20BY%204.0-0a7d55)](LICENSE)
[![Code: MIT](https://img.shields.io/badge/code-MIT-0a7d55)](LICENSE)
[![Self-hosted](https://img.shields.io/badge/self--hosted-docker%20compose-1c5d4a)](#self-hosting)
[![Encryption](https://img.shields.io/badge/scans-encrypted%20in%20browser-1c5d4a)](#how-the-encryption-works)
[![Renewal rules](https://img.shields.io/badge/renewal%20rules-21%20playbooks-1c5d4a)](rules/)

[Use cases](#use-cases) · [Quick start](#quick-start) · [Encryption](#how-the-encryption-works) · [Renewals](#the-renewal-layer) · [Architecture](#two-data-planes) · [Contributing](#helping) · [Security](SECURITY.md)

</div>

---

Your degree certificate, your citizenship certificate, the land deed, your family's papers. Scanned,
sitting in a folder on a laptop you are not currently near — or in a drawer thirty kilometres away.
You will not upload them to Google Drive, and when you actually need one, you cannot reach it.

**That is the problem. Storage is the job.**

Some of those documents also expire, and the renewals are their own trap: a calendar reminder says
*"passport expires 14 March"* and by the time it fires the fourteen weeks you needed are gone. So the
vault knows the renewal process too — but that is the layer on top, not the reason it exists.

<table>
<tr><td width="50%" valign="top">

### 🔒 What it is

An encrypted vault you host yourself.

Scans are encrypted **in your browser**, with a
passphrase that never reaches the server. It
stores ciphertext and holds no key — so a
breach, a backup, or a court order gets bytes.

Your household shares it. Your family's papers
stop being thirty kilometres away.

</td><td width="50%" valign="top">

### 📅 What it also does

Most documents never expire. **Those are just
stored** — no reminders, nothing to chase.

For the ones that do, it works backwards from
the real renewal process:

```
Passport expires   14 Mar 2027
Start by           14 Sep 2026
├── 90d  citizenship certificate
├── 70d  processing (worst case)
└── 21d  buffer
```

</td></tr>
</table>

> **Why not Drive, Dropbox or iCloud?** They can read your files. That is not a flaw in them; it is
> how they work. A passport scan, a land deed and a medical record are exactly the documents where
> that matters, and "we promise not to look" is a different guarantee from "we cannot".

## Contents

- [Use cases](#use-cases)
- [Quick start](#quick-start) · [Self-hosting](#self-hosting)
- [How the encryption works](#how-the-encryption-works)
- [The renewal layer](#the-renewal-layer)
- [Status](#status)
- [What the application does](#what-the-application-does)
- [How a rule works](#how-a-rule-works)
- [What the validator checks](#what-the-validator-checks)
- [Two data planes](#two-data-planes)
- [Repository layout](#repository-layout)
- [Helping](#helping)
- [Licence](#licence)

## Use cases

| You want to… | Start here |
|---|---|
| **Keep documents somewhere only you can read** | [Self-hosting](#self-hosting) — one `docker compose up`, your machine, your keys |
| **Reach your family's papers from another city** | [Quick start](#quick-start) — one household, everyone's documents, [demo included](web/README.md#the-demo) |
| **Understand what the server can and cannot see** | [SECURITY.md](SECURITY.md) — precise, including what it deliberately does *not* protect |
| **Know when something needs renewing** | [The renewal layer](#the-renewal-layer) — worked out from the real process, not the expiry date |
| **Check one renewal without an account** | [`examples/ruby/start_date.rb`](examples/ruby/start_date.rb) — one command, no setup, nothing stored |
| **Build on the open renewal data** | [`examples/`](examples/README.md) — runnable consumers in Ruby, Python, JS and jq |
| **Understand the data format** | [SCHEMA.md](SCHEMA.md) — every field, and why it exists |
| **Fix or verify a renewal figure** | [Claim one](../../issues/new?template=verify-a-rule.md) · [CONTRIBUTING.md](CONTRIBUTING.md) — no toolchain needed |

### Who it is for

Anyone whose important paperwork is scattered across a laptop, a drawer and somebody else's house —
and who would rather not hand scans of it to a company that can read them.

It is sharpest for households split across countries: migrants, work-visa holders, international
students, and people managing a parent's documents from abroad. That is also where the renewal layer
earns its place, because two or three jurisdictions in parallel is the case no other product handles
and the one where a missed deadline costs legal status rather than a late fee.

## Quick start

Needs Ruby 3.3, and MySQL 8.0+ or MariaDB 10.6+ for the application.

<table>
<tr><td valign="top" width="50%">

**The vault** — the actual product

```sh
cd web
bin/setup --skip-server
bin/rails db:seed     # a real drawer
bin/rails server
```

`demo@renewaru.test` / `demo-password-change-me`

</td><td valign="top" width="50%">

**Just the renewal data** — no database, no gems

```sh
ruby bin/validate     # check every rule
ruby bin/build        # site/ + rules.json
ruby examples/ruby/start_date.rb \
  NP passport GB 2027-03-14
```

</td></tr>
</table>

The seeded household is proportioned like a real drawer — **six of its thirteen documents never
expire at all**: a citizenship certificate, a degree, a transcript, a birth certificate, a marriage
certificate, a land deed. They are simply stored, generate no reminders, and are the reason the vault
exists.

The seven that *do* expire cover every state the dashboard can reach. Two of them are the pair worth
looking at:

> **Third-party insurance** — expired a fortnight ago
> **Vehicle registration** — due in two months, and **blocked**, because Nepal will not renew one
> without the other

Both dates look survivable on their own. The renewal is already blocked. Full setup notes, including
the database grant, are in [`web/README.md`](web/README.md).

### Self-hosting

```sh
cp .env.example .env && $EDITOR .env    # generate the secrets, do not choose them
docker compose up -d --build
```

Two containers: the application and MySQL. The app stays a single process — Solid Queue runs inside
Puma, so the nightly reminder sweep is not a service anyone can forget to start. That sweep is the
product.

Back up **both** volumes: `renewaru-db` holds the deadlines, `renewaru-storage` holds the encrypted
attachments, and neither is much use without the other.

> [!WARNING]
> The Docker image has never been built — this was developed without a Docker daemon available. The
> application has been exercised against a real MySQL server; the image around it has not. Build it
> once locally before pointing a domain at it. See [CHANGELOG.md](CHANGELOG.md).

## How the encryption works

The server never has the key. That is not a policy, it is an architecture — there is no code path
that could decrypt an attachment, and none can be added without breaking the tests that guard it.

```mermaid
flowchart LR
    pass(["Your passphrase<br/><i>never sent</i>"]) -->|PBKDF2| key(["AES-GCM key<br/><i>lives in the tab</i>"])
    scan(["Passport scan"]) --> enc["Encrypt in browser"]
    key --> enc
    enc -->|ciphertext + nonce| server[("Server<br/><i>opaque bytes</i>")]
    server -.->|"cannot decrypt"| x(["✗"])
    server -->|ciphertext| dec["Decrypt in browser"]
    key --> dec
    dec --> view(["You read it"])

    style pass fill:#e8f4ee,stroke:#8fc3aa
    style key fill:#e8f4ee,stroke:#8fc3aa
    style server fill:#fdf6e3,stroke:#d9c47a
    style x fill:#fbeeee,stroke:#dda9a9
```

| | |
|---|---|
| **Encrypted in the browser** | The scans themselves. AES-GCM, key derived from a passphrase that is never transmitted. |
| **Encrypted at rest** | Document numbers and free-text notes. |
| **Stored in the clear** | Kind, issuing country, expiry date, names. The server must compute renewal dates and cannot do that over ciphertext. |

That last row is a real trade and [SECURITY.md](SECURITY.md) states it plainly: a database breach
reveals *that someone holds a Nepali passport expiring in March*. It does not reveal the passport.

> **Lose the passphrase and the scans are gone.** There is no recovery, because a recovery path the
> operator can walk is one an attacker or a court order can walk too.

## The renewal layer

Most documents in a vault never expire, and those are simply stored. For the ones that do, this is
what the open dataset in [`rules/`](rules/) is for:

```
start_by = expires_on − processing.worst_case − slowest prerequisite − buffer
```

A real example, from [`rules/np/passport.yml`](rules/np/passport.yml), renewing from the UK:

```mermaid
gantt
    title Nepali passport expiring 14 March 2027, renewed from the UK
    dateFormat  YYYY-MM-DD
    axisFormat  %b %Y
    todayMarker off

    section Allowed but not yet needed
    Window open - no action due   :done, early, 2026-03-14, 184d

    section The work
    Citizenship certificate  90d  :active, prereq, 2026-09-14, 90d
    Processing (worst case)  70d  :active, proc,   after prereq, 70d
    Buffer                   21d  :active, buf,    after proc, 21d

    section Fixed dates
    Window opens                  :milestone, 2026-03-14, 0d
    START BY                      :crit, milestone, 2026-09-14, 0d
    Expires                       :milestone, 2027-03-14, 0d
```

Three consequences follow, and each is load-bearing:

| Decision | Why |
|---|---|
| **`worst_case`, never `typical`** | A date from the median is correct for the median applicant and useless for the tail — and the tail is who a missed deadline destroys. A Nepali driving licence is 30 days typical against **365** worst case. |
| **Prerequisites carry lead time** | A police certificate that itself takes six weeks is not a checklist item; it is six weeks of the plan. Without `obtain_lead_days` the computed date is confidently too late. |
| **A rule can be infeasible, and we say so** | Where the lead time exceeds the window, *no* legal start date finishes in time. Reported, not hidden — it is true, and it is the fact a reader most needs. |

### Reminders anchor to the start date, not the expiry

```mermaid
timeline
    title Five alerts, all anchored to "start by" — not to expiry
    30 days before start : Heads up
    7 days before start  : Soon
    The start date       : Act now
    14 days after        : Overdue
    45 days after        : Critical
```

The cascade continues *past* the start date on purpose: the failure mode is not forgetting, it is
intending to deal with it and not getting round to it. Reminders go by email always, and by web push
where a household has enabled it.

> **No billing state ever stops a reminder.** Somebody whose card expires while abroad is precisely
> who needs the alert, so a lapsed subscription costs capacity — more people, more documents — and
> never safety. There is a test that walks every billing status and asserts it.

## Status

| | |
|---|---|
| Rules | 5 documents, 1 issuing country (Nepal) |
| Playbook pages | 21 |
| Verified | **0 — everything here is `draft`** |
| Infeasible | 9 of 21, reported rather than hidden |

The figures are structured, sourced, and internally consistent. They are **not yet confirmed against
the issuing authorities**, and every page that renders them says so prominently. [Verifying one](#helping)
is the most valuable contribution available.

## What the application does

**The vault**

| | |
|---|---|
| **Encrypted storage** | Scans encrypted in the browser before upload. The server holds ciphertext and no key. |
| **Anything worth keeping** | Degrees, transcripts, birth and marriage certificates, deeds, contracts. **An expiry date is optional** — most documents do not have one. |
| **A household, not an account** | Everyone's documents in one place, so a parent's papers are not thirty kilometres away. |
| **Findable** | Browse and search by label, kind, country or person. Encrypted fields are deliberately not searchable. |
| **Yours** | One `docker compose up` on your own machine. No cloud account required, ever. |

**The renewal layer, for the documents that expire**

| | |
|---|---|
| **Reminder cascade** | Anchored to the start date rather than the expiry date, swept nightly, by email and web push. |
| **Prerequisite chains** | Warns when one document lapsing will block another's renewal. |
| **Playbooks** | Every rule rendered per origin. Server-rendered, no account, crawlable. |
| **Start-date calculator** | Anonymous, nothing stored, the question in the URL so answers can be pasted into a forum thread. |
| **MRZ reading** | From a camera or pasted, with check-digit validation — a misread is caught, not stored as somebody's expiry date. |
| **Installable, offline** | Playbooks cached for a consulate queue or a plane. Public pages only; nothing behind a login touches disk. |

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

One file, several pages: each `(document, origin)` pair renders as its own playbook, because nobody
searches for "Nepali passport renewal" — they search for "from the UK". Full field reference and
design rationale in [SCHEMA.md](SCHEMA.md).

## What the validator checks

`ruby bin/validate` enforces what JSON Schema cannot:

| Check | What it prevents |
|---|---|
| **Provenance** | A rule claiming `verified` without an official government source, a date and a named human. An override cannot inherit trust from a parent it does not share. |
| **Staleness** | A figure nobody has re-read in a year passing as current. Verification older than 365 days fails the build. |
| **Consistency** | A window running backwards, a worst case below the typical, a file whose location disagrees with its contents. |
| **Feasibility** | Silence about processes that cannot be completed in time. **Reported, not rejected** — the data is right and the bureaucracy is the problem. |

## Two data planes

The split is structural, not a convention.

```mermaid
flowchart LR
    contributor(["Contributor<br/>fixing a fee"]) -->|pull request| rules

    subgraph public["🌍 Public plane — versioned, no user data"]
        direction TB
        rules["rules/*.yml"] --> lib["lib/renewaru<br/><i>no gems, no network</i>"]
        lib --> bundle["site/rules.json<br/>+ static playbooks"]
    end

    subgraph private["🔒 Private plane — your database"]
        direction TB
        catalog["RuleCatalog<br/><i>the only bridge</i>"] --> docs[("documents<br/><i>kind · country · expiry</i>")]
        docs --> sweep["nightly sweep"]
        vault[("attachments<br/><i>ciphertext only</i>")]
    end

    lib --> catalog
    bundle --> consumers(["Your app<br/>see examples/"])
    sweep --> alerts(["Email + push"])
    browser(["Your browser<br/><i>holds the key</i>"]) -->|AES-GCM| vault

    style public fill:#e8f4ee,stroke:#8fc3aa
    style private fill:#fdf6e3,stroke:#d9c47a
```

**Public plane** — open, versioned, edited by pull request. No user data, so a contributor correcting
a fee comes nowhere near anybody's passport.

**Private plane** — document metadata is stored in the clear because the server must compute
start-by dates and cannot do that over ciphertext. Identifiers and notes are encrypted at rest.
Attachments are encrypted in the browser and the server has no key. [SECURITY.md](SECURITY.md) is
precise about what that does and does not protect.

Alerts and playbooks are never paywalled. Paywalling the safety feature would poison the trust the
whole thing rests on.

## Repository layout

| Path | What it is |
|---|---|
| [`rules/`](rules/) | The dataset — YAML, one file per country × document |
| [`schema/`](schema/) | The `RenewalRule` contract (JSON Schema 2020-12) |
| [`lib/`](lib/renewaru/) | Loader, timeline arithmetic, validator. No gems, no network. |
| [`bin/`](bin/) | [`validate`](bin/validate) and [`build`](bin/build) |
| [`examples/`](examples/) | Runnable consumers in four languages |
| [`web/`](web/) | The Rails 8 application — [its own README](web/README.md) |
| [`renewal-vault-spec.md`](renewal-vault-spec.md) | The product spec the code comments cite by section |

`rules/` sits at the top of the repository rather than inside `web/` because it is the one part of
this that is published. Somebody correcting a renewal fee should never have to learn that a Rails
application exists — and nothing in `rules/` has ever seen a user's document.

## Helping

**The most valuable contribution is not a new country. It is verifying one that already exists.**

Every rule here says `draft` — the numbers are estimates nobody has checked against the issuing
authority. A wrong renewal date is worse than none, because it replaces a vague worry that prompts
checking with a false precision that prevents it.

```mermaid
flowchart LR
    A["Claim it<br/><i>so two people don't<br/>read the same page</i>"] --> B["Open the authority's<br/>own page"]
    B --> C["Confirm window, processing,<br/>fee, requirements"]
    C --> D["ruby bin/validate"]
    D --> E["Pull request"]
    style A fill:#e8f4ee,stroke:#8fc3aa
    style E fill:#e8f4ee,stroke:#8fc3aa
```

Turning one draft into a sourced `verified` is worth more than five new drafts. It takes an evening
and a government website. [Claim one first](../../issues/new?template=verify-a-rule.md), then see
[CONTRIBUTING.md](CONTRIBUTING.md) for the bar.

Correcting a rule needs **no toolchain**: edit one YAML file, run `ruby bin/validate`, open a pull
request. No bundler, no database, no account.

Other ways in: [report a wrong figure](../../issues/new?template=wrong-rule.md) ·
[request a missing country](../../issues/new?template=missing-rule.md) ·
[report a bug](../../issues/new?template=bug.md) ·
[disclose a vulnerability privately](SECURITY.md)

## Caveat

Community-maintained reference information, **not legal advice**. Government processes change without
notice. Every page shows its last-verified date and links to the authority it came from — confirm
there before acting, and please [open a correction](CONTRIBUTING.md) when you find something wrong.

## Licence

| | |
|---|---|
| Rule data (`rules/`) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) — use it commercially, with attribution |
| Code (`lib/`, `bin/`, `test/`, `web/`) | MIT |

See [LICENSE](LICENSE). Community standards: [Code of Conduct](CODE_OF_CONDUCT.md) ·
[Contributing](CONTRIBUTING.md) · [Security policy](SECURITY.md) · [Changelog](CHANGELOG.md)
