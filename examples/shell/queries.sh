#!/usr/bin/env bash
# Answering questions about the dataset with jq and nothing else.
#
#   ruby bin/build            # writes site/rules.json
#   examples/shell/queries.sh
#
# Needs jq. Every query below runs against the published bundle rather than the
# YAML, because the bundle already carries the derived timeline — no consumer
# has to reimplement the arithmetic, and none of them can get it subtly wrong.

set -euo pipefail

BUNDLE="${BUNDLE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/site/rules.json}"

if [ ! -f "$BUNDLE" ]; then
  echo "$BUNDLE not found — run 'ruby bin/build' first." >&2
  exit 1
fi

rule() { printf '\n\033[1m%s\033[0m\n' "$1"; }

rule "Every playbook, and how early you have to start"
jq -r '.playbooks
       | sort_by(-.timeline.start_days_before_expiry)
       | .[]
       | "  \(.timeline.start_days_before_expiry | tostring | (" " * (4 - length)) + .) days  \(.slug)  [\(.context)]"' "$BUNDLE"

rule "The ones that cannot be finished before expiry, however well you plan"
# Not a data error. Where the total lead time exceeds the renewal window there
# is no legal start date that finishes in time, and that is the fact a reader
# most needs — so it is reported rather than filtered out.
jq -r '.playbooks
       | map(select(.timeline.feasible == false))
       | .[]
       | "  \(.slug) [\(.context)] — \(.timeline.shortfall_days) days short\(if .timeline.covered_by_grace then ", but late renewal is allowed" else ", and there is no grace period" end)"' "$BUNDLE"

rule "How far the worst case diverges from the typical one"
# This gap is the entire argument for planning on the worst case. Where it is
# wide, a reminder built on the median is not slightly early — it is useless.
jq -r '.playbooks
       | map(select(.timeline.worst_case_days > .timeline.typical_days))
       | sort_by(.timeline.typical_days - .timeline.worst_case_days)
       | .[]
       | "  \(.slug) [\(.context)]: \(.timeline.typical_days) typical vs \(.timeline.worst_case_days) worst case"' "$BUNDLE"

rule "Verification status"
jq -r '.playbooks | group_by(.status) | .[] | "  \(.[0].status): \(length)"' "$BUNDLE"

rule "Start date for a specific expiry (NP passport from GB, expiring 2027-03-14)"
# The playbook is bound to $p first: inside the date pipeline `.` is the epoch
# seconds, so `.timeline` there would be looking at a number.
jq -r --arg expiry "2027-03-14" '
  .playbooks
  | map(select(.country_code == "NP" and .document_kind == "passport" and .context == "GB"))[0] as $p
  | ($expiry | strptime("%Y-%m-%d") | mktime) as $at
  | ($at - ($p.timeline.start_days_before_expiry * 86400) | strftime("%Y-%m-%d")) as $start
  | "  start by \($start), \($p.timeline.start_days_before_expiry) days before \($expiry)"
' "$BUNDLE"

printf '\n'
