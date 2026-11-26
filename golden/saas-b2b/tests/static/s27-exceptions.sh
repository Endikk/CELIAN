#!/usr/bin/env bash
# control: S27
# carries: FR-022; research RS-23
#
# The exceptions to the image scan, one file per layer (research RS-23):
# security/scan-exceptions.yaml for the images the project builds, and
# local/security/scan-exceptions.yaml for the images of the local layer.
# Each entry names the vulnerability and the image (its repository written
# in full, without tag or digest), and carries its justification, the date
# it was written and its expiry date, at most max_exception_days later
# (security/scan-policy.yaml). Runs the tests of policy package
# scan_exceptions, then the policy on both files with the date of the day,
# in UTC. Every entry that does not hold is listed and fails the control,
# expired ones included: a passing control prints nothing
# (tests/run-static.sh), and an expired exception must be seen, renewed or
# removed by [SECU].
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
CDPATH='' cd -- "$root"

files="security/scan-exceptions.yaml local/security/scan-exceptions.yaml"
policy_file="security/scan-policy.yaml"

if ! command -v conftest >/dev/null 2>&1; then
  echo "conftest is not installed: run tests/tools/install.sh <dir>, then put <dir> on PATH." >&2
  exit 1
fi

for file in $files $policy_file; do
  if [ ! -f "$file" ]; then
    echo "$file is missing: the scan reads its threshold and its exceptions there (spec 001, T115)." >&2
    exit 1
  fi
done

conftest verify --no-color --policy policy --namespace scan_exceptions

work="$(mktemp -d)"
trap 'rm -rf "${work:?}"' EXIT
printf '{"scan_today": "%s"}\n' "$(date -u +%Y-%m-%d)" >"$work/today.json"

# shellcheck disable=SC2086 # $files is a list of paths without spaces
conftest test --no-color --combine --policy policy --namespace scan_exceptions \
  --data "$policy_file" --data "$work/today.json" $files
