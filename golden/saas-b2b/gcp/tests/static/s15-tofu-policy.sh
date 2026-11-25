#!/usr/bin/env bash
# control: S15
# carries: FR-011, FR-012; ADR-008, conditions 1 to 6 and 8; ADR-007, condition 2; ADR-010; R-32; R-05, R-17, R-18
#
# Two parts, both on the HCL of gcp/tofu/, without any credential:
# - policy: the tests of the conftest packages of gcp/policy/, then each
#   failing case of gcp/policy/testdata/, which must be refused with the
#   message its "# expect:" line gives, then the packages on the root;
# - scan: Trivy on the root. Each finding is fixed, or justified in writing
#   right above its resource with a "#trivy:ignore:<ID>" comment (T109). No
#   .trivyignore file is read, and nothing is sent to Aqua (research RS-22).
#
# Usage: gcp/tests/static/s15-tofu-policy.sh [policy|scan]
# Without argument, both parts: that is how `task check` runs it, through
# tests/run-static.sh. `task gcp:policy` and `task gcp:scan` run one each.
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
CDPATH='' cd -- "$root"

part="${1:-both}"
dir="gcp/tofu"
policies="gcp/policy"
packages="tofu_adr008 tofu_secret_sync tofu_config_sync tofu_finops"
problems=0

case "$part" in
  policy | scan | both) ;;
  *)
    echo "usage: gcp/tests/static/s15-tofu-policy.sh [policy|scan]" >&2
    exit 1
    ;;
esac

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is not installed: run tests/tools/install.sh <dir>, then put <dir> on PATH." >&2
    exit 1
  fi
}

# Value of the "# <key>: <value>" line of file $2, in its first lines.
header_value() {
  awk -v key="# $1: " \
    'NR > 10 { exit } index($0, key) == 1 { print substr($0, length(key) + 1); exit }' "$2"
}

# True when the root has its .tf files; says what is missing otherwise.
root_present() {
  set -- "$dir"/*.tf
  if [ ! -f "$1" ]; then
    echo "$dir holds no .tf file: the OpenTofu root of the gcp layer is missing (T106 to T108)." >&2
    problems=$((problems + 1))
    return 1
  fi
}


# Each failing case is refused, by a message that holds its "# expect:" text.
check_cases() {
  local case_file package expect out found=0
  for case_file in "$policies"/testdata/*.tf; do
    [ -f "$case_file" ] || continue
    found=$((found + 1))
    package="$(header_value package "$case_file")"
    expect="$(header_value expect "$case_file")"
    if [ -z "$package" ] || [ -z "$expect" ]; then
      echo "$case_file: no '# package:' or '# expect:' line." >&2
      problems=$((problems + 1))
      continue
    fi
    if out="$(conftest test --no-color --combine --policy "$policies" --namespace "$package" "$case_file" platform.yaml 2>&1)"; then
      echo "$case_file: accepted by $package, yet it is a failing case: $expect" >&2
      problems=$((problems + 1))
    elif ! printf '%s\n' "$out" | grep -F -q -e "$expect"; then
      echo "$case_file: refused by $package, but no message holds: $expect" >&2
      printf '%s\n' "$out" >&2
      problems=$((problems + 1))
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo "$policies/testdata holds no failing case." >&2
    problems=$((problems + 1))
  fi
}

run_policy() {
  local package
  need conftest
  # One package per run: conftest says nothing about a package it does not
  # find (research RS-18), and tests/run-static.sh refuses a policy that no
  # control script names.
  for package in $packages; do
    conftest verify --no-color --policy "$policies" --namespace "$package" || problems=$((problems + 1))
  done
  check_cases
  root_present || return 0
  for package in $packages; do
    conftest test --no-color --combine --policy "$policies" --namespace "$package" "$dir"/*.tf platform.yaml ||
      problems=$((problems + 1))
  done
}

# Trivy in an emptied environment, with its cache in a temporary directory:
# the checks bundle is fetched again at each run, so that a new rule shows.
run_scan() {
  local work
  need trivy
  root_present || return 0
  work="$(mktemp -d)"
  mkdir -p "$work/home"
  if ! env -i PATH="$PATH" HOME="$work/home" trivy config --quiet \
    --cache-dir "$work/cache" --disable-telemetry --ignorefile '' \
    --misconfig-scanners terraform --exit-code 1 "$dir"; then
    echo "Trivy refuses $dir: fix each finding, or justify it right above its resource (T109)." >&2
    problems=$((problems + 1))
  fi
  rm -rf "$work"
}

case "$part" in
  policy) run_policy ;;
  scan) run_scan ;;
  both)
    run_policy
    run_scan
    ;;
esac

if [ "$problems" -gt 0 ]; then
  exit 1
fi
