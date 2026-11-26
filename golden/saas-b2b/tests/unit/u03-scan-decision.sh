#!/usr/bin/env bash
# control: U03
# carries: FR-022; research RS-23; story 7, scenarios 3 to 5
#
# The decision of the image scan, on example reports and at a fixed date,
# without network and without a vulnerable image (research RS-23):
# - the tests of policy package scan_decision (policy/scan_decision_test.rego);
# - each case of tests/scan-reports/cases/: its report.json and its
#   exceptions.yaml go through the same conftest command as the scan
#   (tests/scan/scan-images.sh), with the policy, the date and the platform of
#   tests/scan-reports/ (linux/arm64). Its expect file gives "pass" or "deny"
#   on the first line, then one text per line that the output must hold. They
#   include the cases of the second PR of step 18: a report that holds neither
#   Results nor Metadata.OS, a report of the amd64 variant in an arm64 run, an
#   image on a system at the end of life, and the report of the lock file of the
#   front (a HIGH finding, no Results, clean).
# Called by `task test` and by the job unit of
# .github/workflows/golden-saas-b2b.yml.
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
CDPATH='' cd -- "$root"

reports="tests/scan-reports"
problems=0

fail() {
  printf 'U03: %s\n' "$1" >&2
  problems=$((problems + 1))
}

if ! command -v conftest >/dev/null 2>&1; then
  printf 'U03: conftest is not installed: run tests/tools/install.sh <dir>, then put <dir> on PATH.\n' >&2
  exit 1
fi

conftest verify --no-color --policy policy --namespace scan_decision || fail "the tests of policy package scan_decision fail."

found=0
for dir in "$reports"/cases/*/; do
  dir="${dir%/}"
  [ -f "$dir/expect" ] || continue
  found=$((found + 1))
  expected="$(head -n 1 "$dir/expect")"
  if out="$(conftest test --no-color --combine --policy policy --namespace scan_decision \
    --data "$reports/scan-policy.yaml" --data "$reports/today.yaml" \
    "$dir/report.json" "$dir/exceptions.yaml" 2>&1)"; then
    outcome="pass"
  else
    outcome="deny"
  fi
  if [ "$outcome" != "$expected" ]; then
    fail "$dir: the decision is \"$outcome\", \"$expected\" expected."
    printf '%s\n' "$out" >&2
    continue
  fi
  while IFS= read -r text || [ -n "$text" ]; do
    [ -n "$text" ] || continue
    if ! printf '%s\n' "$out" | grep -F -q -e "$text"; then
      fail "$dir: no line of the decision holds: $text"
      printf '%s\n' "$out" >&2
    fi
  done < <(tail -n +2 "$dir/expect")
done

if [ "$found" -eq 0 ]; then
  fail "$reports/cases holds no case."
fi

if [ "$problems" -gt 0 ]; then
  exit 1
fi
printf 'U03: the decision of the scan holds on %s example cases.\n' "$found"
