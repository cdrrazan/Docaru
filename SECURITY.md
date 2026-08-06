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

**Held elsewhere, on purpose.** Card details are never seen by this application. Checkout is opened
by redirecting to Paddle, who are the merchant of record; what comes back is a subscription
identifier and a status. There is no card number, no expiry, and no billing address in this database
to steal.

**Push subscriptions**, where a household has enabled them: an endpoint URL belonging to the
browser's own push service, plus the two keys a message is encrypted to. These identify a browser
rather than a person, they are revocable from the dashboard, and they are scoped to the individual
user rather than the household — nobody else can enumerate or revoke somebody's device.

## Two things the design deliberately does not cache

Both are places where an obvious convenience would quietly undo the paragraphs above, so they are
called out rather than left to be rediscovered.

**The service worker caches by allowlist, never denylist.** Only public playbook pages and static
assets are stored offline. Caching a dashboard would write document metadata into CacheStorage, where
it outlives signing out and is readable by whoever picks the device up next. A private route added
later is excluded by default rather than by somebody remembering to exclude it.

**Notification bodies carry the deadline.** A reminder says which document and by when, which means
it is legible on a lock screen. That is a deliberate trade: a notification that says "you have an
update" wastes the only sentence it gets, and the alert landing in time is the entire product. Anyone
for whom that is the wrong trade can leave push off and receive email only.

## Things that are not vulnerabilities

- **Losing the vault passphrase loses the scans.** There is no recovery. A recovery path the
  operator can walk is a recovery path an attacker or a court order can walk.
- **Renewal rule data being wrong.** That is a correctness bug — please
  [open an issue](CONTRIBUTING.md), it matters, but it is not a security issue.
- **Metadata being readable server-side.** Documented above as a design decision.
- **A notification body naming a document.** Also a design decision, above. Turn push off to opt out.
- **Reminders continuing after a payment fails.** Intended, and load-bearing. Somebody whose card
  expires while they are abroad is exactly the person most likely to need the alert, so no billing
  state ever stops one. There is a test that asserts it.

## Self-hosting

Generate every secret in `.env.example` rather than choosing one, and put the instance behind TLS.

Back up both volumes: the MySQL data directory holds the deadlines, and `/rails/storage` holds the
encrypted attachments. Neither is much use without the other, and the attachments are unreadable
without the vault passphrase regardless — which is the point, and also means a backup of them alone
protects nobody who has forgotten it.

Do not expose the database port publicly. The compose file keeps MySQL on the internal network with
no published port, which is deliberate.

An instance without working SMTP sends no reminders, which means it does not do the one thing it
exists for; check that first.

Push and billing are both optional and both off until their keys are set. Two things about them if
you do switch them on:

- **Generate the VAPID pair once and keep it.** Rotating it silently invalidates every subscription
  your users have already granted, and browsers will not prompt them again.
- **`PADDLE_ENVIRONMENT` defaults to `sandbox`.** Of the two ways to get that wrong, the one that
  cannot charge anybody is the better default. Set it to `production` only when you mean it.
