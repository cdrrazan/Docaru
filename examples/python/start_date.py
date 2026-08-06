#!/usr/bin/env python3
"""Reading the published bundle from a language that is not Ruby.

    ruby bin/build                                    # writes site/rules.json
    python3 examples/python/start_date.py NP passport GB 2027-03-14

Standard library only. The point of this example is what it does *not* do: it
never recomputes the arithmetic. `start_days_before_expiry` is already in the
bundle, worked out from the worst case, the slowest prerequisite and the buffer.
Reimplementing that in each consumer is how five tools end up disagreeing about
one passport, and four of them are wrong in the direction that costs somebody a
visa.
"""

import json
import sys
from datetime import date, timedelta
from pathlib import Path

BUNDLE = Path(__file__).resolve().parents[2] / "site" / "rules.json"


def load():
    if not BUNDLE.exists():
        sys.exit(f"{BUNDLE} not found — run `ruby bin/build` first.")
    return json.loads(BUNDLE.read_text(encoding="utf-8"))


def find(playbooks, country, kind, origin):
    kind = kind.replace("-", "_")
    country = country.upper()
    wanted = "domestic" if origin.lower() == "domestic" else origin.upper()

    matches = [
        p for p in playbooks
        if p["country_code"] == country and p["document_kind"] == kind
    ]
    if not matches:
        sys.exit(f"No rule for {country}/{kind}.")

    # An origin with no override of its own is not an error. Fall back to any
    # non-domestic context rather than to the domestic one: domestic timings
    # given to somebody abroad are months too optimistic.
    for playbook in matches:
        if playbook["context"] == wanted:
            return playbook

    if wanted != "domestic":
        abroad = [p for p in matches if p["context"] != "domestic"]
        if abroad:
            # The slowest of the known missions, not the first one in the file.
            # Guessing has to err towards starting too early: the cost of that
            # is waiting, and the cost of the other is a lapsed document.
            slowest = max(abroad, key=lambda p: p["timeline"]["start_days_before_expiry"])
            print(f"note: no entry for {wanted}; using the slowest known origin "
                  f"({slowest['context']}) rather than guessing low", file=sys.stderr)
            return slowest

    return matches[0]


def main():
    if len(sys.argv) != 5:
        sys.exit("usage: start_date.py <COUNTRY> <DOCUMENT_KIND> <FROM|domestic> <YYYY-MM-DD>")

    _, country, kind, origin, expires_on = sys.argv
    bundle = load()
    playbook = find(bundle["playbooks"], country, kind, origin)
    timeline = playbook["timeline"]

    expiry = date.fromisoformat(expires_on)
    start_by = expiry - timedelta(days=timeline["start_days_before_expiry"])

    print(f"{playbook['title']} — {playbook['context']}")
    print(f"  expires    {expiry}")
    print(f"  start by   {start_by}  ({timeline['start_days_before_expiry']} days before expiry)")
    print(f"  lead time  {timeline['required_lead_days']} days "
          f"({timeline['worst_case_days']} worst case, {timeline['typical_days']} typical)")

    if not timeline["feasible"]:
        # A true fact about the process, not a defect in the data. Surface it;
        # the reader needs to plan around a gap rather than around a deadline.
        short = timeline["shortfall_days"]
        grace = " Late renewal is permitted here." if timeline["covered_by_grace"] else ""
        print(f"  WARNING    cannot be finished before expiry — about {short} days late.{grace}")

    if playbook["status"] == "draft":
        print("  UNVERIFIED no human has checked these figures against the authority.")

    return 0 if timeline["feasible"] else 2


if __name__ == "__main__":
    sys.exit(main())
