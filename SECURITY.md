# Security

## Reporting a vulnerability

Report privately through [GitHub's advisory form](https://github.com/cdrrazan/Renewaru/security/advisories/new),
or by email to the address on the maintainer's GitHub profile. Please do not open a public issue for
anything exploitable.

Include what you did, what happened, and what you expected. A proof of concept helps. You will get an
acknowledgement within a few days and an assessment within two weeks.

Please do not run automated scanners against a hosted instance, and do not access, modify, or retain
data belonging to anyone else while investigating. Testing against your own self-hosted instance is
always fine and is the preferred route.

## What this application holds

Worth being precise about, because the answer shapes what a breach would actually mean.

**Public, and not sensitive at all.** The renewal rules in `rules/`. They are a published dataset —
copying them is not a breach, it is the licence.

**Private, and stored in the clear.** Document kind, issuing country, expiry date, the country a
renewal is being made from, member names, household names, email addresses. This is deliberate: the
server has to compute start-by dates and render dashboards, and it cannot do either over ciphertext.

The consequence, stated plainly: a database breach reveals *that someone holds a Nepali passport
expiring in March and is renewing it from Qatar*. For a migrant that is not nothing. It is the price
of a product that can compute the deadline at all, and the trade is made knowingly rather than
hidden.

**Private, encrypted at rest.** Document identifiers (passport numbers and similar) and free-text
notes, via ActiveRecord encryption with keys supplied from the environment. Neither is needed to
compute a date, so neither is available to the running query path.

**Private, encrypted in the browser.** Attachments — the actual scans. Encrypted with AES-GCM using a
key derived from a vault passphrase that is never transmitted. The server stores ciphertext, a nonce,
and a content type. It has no key, no way to obtain one, and no code path that decrypts.

That last property is the one worth attacking, and the one worth reporting on if you find it is not
true.

## Things that are not vulnerabilities

- **Losing the vault passphrase loses the scans.** There is no recovery. A recovery path the
  operator can walk is a recovery path an attacker or a court order can walk.
- **Renewal rule data being wrong.** That is a correctness bug — please
  [open an issue](CONTRIBUTING.md), it matters, but it is not a security issue.
- **Metadata being readable server-side.** Documented above as a design decision.

## Self-hosting

Generate every secret in `.env.example` rather than choosing one, put the instance behind TLS, and
back up `/rails/storage` — it holds both the databases and the encrypted attachments. An instance
without working SMTP sends no reminders, which means it does not do the one thing it exists for;
check that first.
