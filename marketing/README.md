# The marketing site

The shopfront at `docaru.com`. The Rails application is a separate deployment at
`app.docaru.com`; this site links to it and never talks to it.

```sh
nvm use            # 22.18.0, see .nvmrc — Astro 7 needs >= 22.12
npm install
npm run dev        # http://localhost:4321
npm run build      # -> dist/
```

## Why this is a third thing in the repository

The repository already had two planes — the public rule dataset at the root and the Rails app in
`web/` — and this is neither. It exists because marketing copy should be able to change without a
Rails deploy, and because the front page is the one surface where design effort pays for itself.

It is **static, not a single-page app.** Organic search is the acquisition channel: the 21 playbook
pages are the top of the funnel and this site is what they convert against. `npm run build` emits
four HTML files with the CSS inlined, no JavaScript, and no external requests. If a page ever needs
`client:` on a component, that is worth arguing about first — a crawler is the primary reader here.

## What lives where

| | Here (`docaru.com`) | The app (`app.docaru.com`) |
|---|---|---|
| Homepage, pricing, security, self-hosting | ✓ | |
| Playbooks, the calculator | | ✓ |
| Sign-in, vault, dashboard, billing | | ✓ |

The calculator stays in the Rails app deliberately. `Docaru::Timeline` owns the phrasing of every
verdict precisely so the app and the static generator cannot describe one rule two ways; a
JavaScript reimplementation here would be a third source of truth for the one number this product
exists to compute.

## Things that are duplicated on purpose

- **The palette**, in `src/styles/global.css`. It is copied from the app's `application.css` rather
  than shared, because sharing it would couple two deployments on two schedules for the sake of
  twelve custom properties. Both files carry a comment saying so.
- **The prices**, in `src/pages/pricing.astro`. The app's own `/plan` page reads the real numbers out
  of `Household::STORAGE_LIMITS`. If the two ever disagree, **the app is right and this is stale.**

## Deploying

Cloudflare Pages, build command `npm run build`, output directory `dist`, and set `SITE_URL` and
`PUBLIC_APP_URL` for anything that is not production. Both have production defaults, so a build with
no environment set produces the live site rather than something broken.
