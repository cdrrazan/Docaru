#!/usr/bin/env node
// The same read from Node, with no dependencies.
//
//   ruby bin/build                                                  # writes site/rules.json
//   node examples/javascript/start-date.mjs NP passport GB 2027-03-14
//
// Dates are done in UTC on purpose. A renewal deadline is a calendar date, not
// an instant, and `new Date("2027-03-14")` parsed as local time then formatted
// back can move it by a day — which is a whole day of a plan, in the direction
// nobody wants.

import { readFileSync, existsSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..")
const bundlePath = join(root, "site", "rules.json")

const [, , country, kind, origin, expiresOn] = process.argv
if (!expiresOn) {
  console.error("usage: start-date.mjs <COUNTRY> <DOCUMENT_KIND> <FROM|domestic> <YYYY-MM-DD>")
  process.exit(1)
}

if (!existsSync(bundlePath)) {
  console.error(`${bundlePath} not found — run \`ruby bin/build\` first.`)
  process.exit(1)
}

const { playbooks } = JSON.parse(readFileSync(bundlePath, "utf8"))

const wanted = origin.toLowerCase() === "domestic" ? "domestic" : origin.toUpperCase()
const matches = playbooks.filter(
  (p) => p.country_code === country.toUpperCase() && p.document_kind === kind.replaceAll("-", "_")
)

if (matches.length === 0) {
  console.error(`No rule for ${country}/${kind}.`)
  process.exit(1)
}

function pick() {
  const exact = matches.find((p) => p.context === wanted)
  if (exact) return exact

  if (wanted !== "domestic") {
    const abroad = matches.filter((p) => p.context !== "domestic")
    if (abroad.length) {
      // The slowest known mission rather than the first in the file. A guess
      // here has to err towards starting too early: the cost of that is
      // waiting, and the cost of the other is a lapsed document.
      const slowest = abroad.reduce((a, b) =>
        b.timeline.start_days_before_expiry > a.timeline.start_days_before_expiry ? b : a
      )
      console.error(`note: no entry for ${wanted}; using the slowest known origin (${slowest.context})`)
      return slowest
    }
  }

  return matches[0]
}

const playbook = pick()
const { timeline } = playbook

const expiry = new Date(`${expiresOn}T00:00:00Z`)
const startBy = new Date(expiry)
startBy.setUTCDate(startBy.getUTCDate() - timeline.start_days_before_expiry)

const iso = (d) => d.toISOString().slice(0, 10)

console.log(`${playbook.title} — ${playbook.context}`)
console.log(`  expires    ${iso(expiry)}`)
console.log(`  start by   ${iso(startBy)}  (${timeline.start_days_before_expiry} days before expiry)`)
console.log(
  `  lead time  ${timeline.required_lead_days} days ` +
    `(${timeline.worst_case_days} worst case, ${timeline.typical_days} typical)`
)

if (!timeline.feasible) {
  const grace = timeline.covered_by_grace ? " Late renewal is permitted here." : ""
  console.log(`  WARNING    cannot be finished before expiry — about ${timeline.shortfall_days} days late.${grace}`)
}

if (playbook.status === "draft") {
  console.log("  UNVERIFIED no human has checked these figures against the authority.")
}

process.exit(timeline.feasible ? 0 : 2)
