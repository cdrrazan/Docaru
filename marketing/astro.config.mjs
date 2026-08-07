// @ts-check
import { defineConfig } from "astro/config"

// Static output, no adapter, no islands.
//
// The reason this site exists as its own thing is that marketing should deploy
// without a Rails deploy — not that it needs a framework. Every page here is
// content, so every page here is HTML by the time it reaches a CDN. Astro is
// used for components and layouts and then gets out of the way; if a page ever
// needs `client:` on anything, that is worth an argument first, because a
// crawler is the primary reader of this site and the acquisition channel runs
// through it.
export default defineConfig({
  site: process.env.SITE_URL || "https://docaru.com",
  output: "static",
  // The app is a different origin. Trailing-slash consistency matters because
  // the canonical URLs here have to match what the sitemap and the Rails app
  // link to, and "/pricing" and "/pricing/" are two pages to a crawler.
  trailingSlash: "never",
  build: { format: "file" },
  devToolbar: { enabled: false }
})
