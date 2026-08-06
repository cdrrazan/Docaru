# Contributing a renewal rule

Every rule is one YAML file. Correcting one is editing that file and opening a pull request —
there is no build to set up, no account to make, and no user data anywhere near this repository.

**The most useful contribution is not a new country. It is verifying one that already exists.**
Most rules here are marked `draft`, meaning the numbers are estimates nobody has checked against
the issuing authority. Turning a single `draft` into a sourced `verified` is worth more than five
new drafts, because a wrong renewal date is worse than no page at all.

---

## Editing a rule

1. Find the file: `rules/<country>/<document-kind>.yml`.
2. Change it. [`SCHEMA.md`](SCHEMA.md) explains what each field means and why it exists.
3. Check your work:

   ```sh
   ruby bin/validate
   ```

   Ruby 3.4.10 or newer and nothing else — no gems, no bundler. If that command passes, CI will pass.

4. Open a pull request describing what you changed and linking the page you got it from.

To preview the pages your change produces:

```sh
ruby bin/build && open site/index.html
```

## Adding a country or a document

Copy the closest existing file and edit it. Two conventions the validator enforces, so that a rule
can always be found from its identity:

- the directory is the lowercased `country_code` — `NP` lives in `rules/np/`
- the filename is the `document_kind` with underscores as dashes — `police_clearance` is `police-clearance.yml`

`document_kind` is a closed list in [`schema/renewal-rule.schema.json`](schema/renewal-rule.schema.json).
If your document genuinely is not on it, add it there in the same pull request and say why — it is
closed so that the app consuming this data never meets a kind it has no interface for, not to keep
anyone out.

## Verifying a rule

This is the part that matters, so it has a bar.

To move a rule from `draft` to `verified`:

- [ ] Open the issuing authority's **own** page and read the current figures there.
- [ ] Confirm each of: the renewal window, processing time, fee, and the required document list.
- [ ] Put that page in `source_urls`. At least one source must be an official government domain —
      the validator checks this and will reject `verified` without one.
- [ ] Set `verified_on` to today and `verified_by` to your GitHub handle.
- [ ] Say in the pull request which figures changed and which you confirmed unchanged.

Blogs, visa agents, and forum posts are fine as *supporting* sources and are not sufficient on
their own. They are frequently copied from each other and are often years out of date; that is
exactly the failure this dataset exists to avoid reproducing.

Verification expires. CI fails any rule verified more than 365 days ago, which is deliberate: a
figure nobody has looked at in a year is not a verified figure, it is an old one.

## Estimating honestly

Where you cannot confirm something, leave it `draft` rather than guessing quietly. A `draft` rule
renders with a visible warning on every page and is genuinely useful; a confident wrong number is not.

Two fields decide whether the output is any good:

**`worst_case`, not typical.** Processing times are recorded as a range because reminders are
computed from the worst case. A date derived from the median is correct for the median applicant
and useless for everyone in the tail — and the tail is where a missed deadline costs someone their
job or their legal status. If you only know the typical figure, set `worst_case` to the longest
outcome you have actually seen reported.

**`obtain_lead_days` on prerequisites.** If a required document takes six weeks to get, that is six
weeks of the plan, not a checklist item. This field is what turns "renew by March" into "start in
November". Leaving it off produces a start date that is confidently too late.

## What does not belong here

- Personal documents, scans, or anybody's data. This repository is public reference data only.
- Agent, broker, or paid-service links. Link the authority.
- Legal advice, or anything phrased as a guarantee. These pages describe a process; they do not
  promise an outcome.

## Reporting something wrong without editing YAML

Open an issue saying which page is wrong, what it should say, and where you saw that. That is a
completely legitimate contribution, and it is how most corrections start.
