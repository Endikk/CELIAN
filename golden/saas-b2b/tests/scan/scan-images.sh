#!/usr/bin/env bash
# Scans the pulled images of the inventory of a profile (spec 001, FR-021,
# FR-022; research RS-22 to RS-24), then decides with the policy of the
# repository:
# - the inventory comes from local/scripts/image-inventory.sh. The images
#   under saas-b2b.invalid are built by task up and scanned in the job that
#   runs them, with the second PR of step 18: this script names them and
#   skips them;
# - Trivy, installed and checked by tests/tools/install.sh, writes one JSON
#   report per image, every severity kept. It runs under env -i, with its
#   cache and its HOME in a directory of this run, removed at the end: the
#   vulnerability database is downloaded in each run, from its default
#   repositories, and kept nowhere. The options are those of research RS-22;
#   S26 reads them through a fake trivy;
# - conftest runs policy/scan_decision.rego on the reports, the two
#   exception files, the policy of security/scan-policy.yaml and the date of
#   the day in UTC. It refuses each image and vulnerability at or above the
#   threshold without a valid exception, naming both, on the images that go to
#   production or that no class holds (blocking and unclassified, decision of
#   the DSI of 2026-11-25). The reported images, third-party images of the
#   local cluster, do not block: a table of them (image, CRITICAL, HIGH,
#   distinct identifiers, with a fix) goes to the output and to
#   $GITHUB_STEP_SUMMARY when it is set.
# Fails when Trivy fails, saying so when the database could not be
# downloaded (spec 001, edge case): the scan never passes without it.
#
# Usage: tests/scan/scan-images.sh [--db-repository <repository>] lite
# --db-repository serves the E27 case only, and is refused outside a host
# under .invalid, which resolves to no registry (research RS-07; S26).
# Needs the network: the database, then each image from its registry.
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
CDPATH='' cd -- "$root"

policy_file="security/scan-policy.yaml"
exception_files="security/scan-exceptions.yaml local/security/scan-exceptions.yaml"
# The platform of the CI runners and of the cluster of e2e-lite. The arm64
# variant of each index is not scanned (tasks.md, gap 58).
platform="linux/amd64"
# Trivy stops at 5m0s by default (research RS-22); the node image is the
# heaviest of the inventory.
trivy_timeout="10m"
pass_line="no pulled blocking image carries a vulnerability at or above the threshold without a valid exception; the images built by task up (saas-b2b.invalid) are scanned from the second PR of step 18"

usage="usage: tests/scan/scan-images.sh [--db-repository <repository under .invalid>] lite"

fail() {
  printf 'E27: %s\n' "$1" >&2
  exit 1
}

db_repository=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --db-repository)
      [ "$#" -ge 2 ] || fail "$usage"
      db_repository="$2"
      shift 2
      ;;
    -*) fail "$usage" ;;
    *) break ;;
  esac
done
[ "$#" -eq 1 ] || fail "$usage"
profile="$1"

if [ -n "$db_repository" ]; then
  case "${db_repository%%/*}" in
    *.invalid) ;;
    *)
      printf 'S26: %s: the vulnerability database comes from the default repositories of Trivy only; --db-repository serves the E27 case, under a host in .invalid (research RS-22).\n' "$db_repository" >&2
      exit 1
      ;;
  esac
fi

for tool in trivy conftest; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    fail "$tool is not installed: run tests/tools/install.sh <dir>, then put <dir> on PATH."
  fi
done
# shellcheck disable=SC2086 # $exception_files is a list of paths without spaces
for file in "$policy_file" $exception_files; do
  [ -f "$file" ] || fail "$file is missing: the scan reads its threshold and its exceptions there."
done

refs="$(bash local/scripts/image-inventory.sh "$profile")" || fail "the inventory of the $profile profile fails (message above)."

work="$(mktemp -d)"
trap 'rm -rf "${work:?}"' EXIT
mkdir -p "$work/home" "$work/reports"

# Trivy on image $1, its JSON report written to $2 (research RS-22).
run_trivy() {
  local ref="$1" output="$2"
  set -- image --quiet --config '' --cache-dir "$work/cache" \
    --disable-telemetry --skip-version-check --ignorefile '' \
    --scanners vuln --image-src remote --platform "$platform" --offline-scan \
    --timeout "$trivy_timeout" --exit-code 0 --format json --output "$output"
  if [ -n "$db_repository" ]; then
    set -- "$@" --db-repository "$db_repository"
  fi
  env -i PATH="$PATH" HOME="$work/home" trivy "$@" "$ref"
}

scanned=0
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  case "$ref" in
    saas-b2b.invalid/*)
      printf 'E27: %s is built by task up; it is scanned in the job that runs it, from the second PR of step 18.\n' "$ref"
      continue
      ;;
  esac
  scanned=$((scanned + 1))
  printf 'E27: scanning %s\n' "$ref"
  if ! run_trivy "$ref" "$work/reports/$scanned.json" 2>"$work/trivy.err"; then
    cat "$work/trivy.err" >&2
    if grep -q 'failed to download vulnerability DB' "$work/trivy.err"; then
      fail "the vulnerability database could not be downloaded${db_repository:+ from $db_repository}: the scan fails, and never passes without a database fetched in this run (spec 001, edge case; research RS-22)."
    fi
    fail "Trivy could not scan $ref (message above)."
  fi
done < <(printf '%s\n' "$refs")

[ "$scanned" -gt 0 ] || fail "the inventory of the $profile profile holds no pulled image."

printf '{"scan_today": "%s"}\n' "$(date -u +%Y-%m-%d)" >"$work/today.json"
decision=0
# shellcheck disable=SC2086 # $exception_files is a list of paths without spaces
conftest test --no-color --combine --policy policy --namespace scan_decision \
  --data "$policy_file" --data "$work/today.json" "$work"/reports/*.json $exception_files >"$work/decision.txt" 2>&1 || decision=$?
cat "$work/decision.txt"

# The reported images, third-party images of the local cluster that do not
# block (decision of the DSI, 2026-11-25): one row each, from the "reported:"
# lines of the decision, in the output and in the summary of the job.
awk '
  BEGIN {
    print "| Image | CRITICAL | HIGH | Distinct identifiers | With a fix |"
    print "| --- | --- | --- | --- | --- |"
  }
  # Anchored on the start of a WARN line: the deny lines carry package names
  # that come from the reports.
  /^WARN - .* reported: [^ ]+: [0-9]+ CRITICAL, / {
    line = $0
    sub(/^WARN - .* reported: /, "", line)
    image = line
    sub(/: [0-9]+ CRITICAL, .*$/, "", image)
    rest = line
    sub(/^[^ ]+: /, "", rest)
    split(rest, p, /[ ,;]+/)
    # p: 1 and 3 count CRITICAL and HIGH, 5 the distinct identifiers, 11 those with a fix
    print "| " image " | " p[1] " | " p[3] " | " p[5] " | " p[11] " |"
  }
' "$work/decision.txt" >"$work/table.md"
printf '\nE27: reported images (not blocking; [SECU] reads them at the monthly review of the advisories):\n'
cat "$work/table.md"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    printf '### Image scan: reported images\n\n'
    printf 'Third-party images that run on the local cluster only. Their findings at or above the threshold do not block; [SECU] reads this table.\n\n'
    cat "$work/table.md"
    printf '\n'
  } >>"$GITHUB_STEP_SUMMARY"
fi

if [ "$decision" -ne 0 ]; then
  fail "the scan refuses the images above: each vulnerability at or above the threshold of $policy_file, on an image that goes to production or that no class holds, needs a fix or a valid exception written by [SECU] (FR-022)."
fi
printf 'E27: %s pulled images scanned; %s.\n' "$scanned" "$pass_line"
