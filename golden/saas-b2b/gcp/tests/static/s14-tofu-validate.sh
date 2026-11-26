#!/usr/bin/env bash
# control: S14
# carries: FR-011; ADR-008, condition 7; constitution, principle X
#
# The two OpenTofu roots of the gcp layer, gcp/tofu/ and the budget root
# gcp/budget/ (T110), are formatted, initialize against their versioned lock
# without changing it, and validate, without any backend or credential (spec
# 001, plan, S14). `task gcp:validate` runs this script; `task check` runs it
# through tests/run-static.sh.
#
# OpenTofu runs in an emptied environment: PATH and a temporary HOME only.
# No credential of the workstation can reach it. `tofu validate` never builds
# the gcp_kms key of the encryption block, but a command that reads the state
# does, with whatever credential it finds (research RS-16). Its working data,
# downloaded providers included, goes to a temporary TF_DATA_DIR removed at
# exit: nothing lands in the tree. The init needs the registry of OpenTofu.
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
CDPATH='' cd -- "$root"

roots="gcp/tofu gcp/budget"

if ! command -v tofu >/dev/null 2>&1; then
  echo "OpenTofu is not installed: run tests/tools/install.sh <dir>, then put <dir> on PATH." >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/home"

# Runs its arguments with PATH, a temporary HOME and the data directory only.
# TF_IN_AUTOMATION keeps OpenTofu from suggesting the next command. $1 is the
# data directory of the root being checked.
sandboxed() {
  local data="$1"
  shift
  env -i PATH="$PATH" HOME="$work/home" TF_DATA_DIR="$data" TF_IN_AUTOMATION=1 "$@"
}

problems=0

# Value of the "# <key>: <value>" line of file $2, in its first lines.
header_value() {
  awk -v key="# $1: " \
    'NR > 10 { exit } index($0, key) == 1 { print substr($0, length(key) + 1); exit }' "$2"
}

# One line for each provider block of the lock file $1 that is not on the
# registry of OpenTofu. Stub: refuses nothing yet.
lock_findings() {
  return 0
}

# Each failing lock of gcp/tests/static/s14-cases/ is refused, by a message
# that holds its "# expect:" text.
check_lock_cases() {
  local case_file expect out found=0
  for case_file in gcp/tests/static/s14-cases/*.hcl; do
    [ -f "$case_file" ] || continue
    found=$((found + 1))
    expect="$(header_value expect "$case_file")"
    out="$(lock_findings "$case_file")"
    if [ -z "$out" ]; then
      echo "$case_file: accepted, yet it is a failing lock: $expect" >&2
      problems=$((problems + 1))
    elif ! printf '%s\n' "$out" | grep -F -q -e "$expect"; then
      echo "$case_file: refused, but no message holds: $expect" >&2
      printf '%s\n' "$out" >&2
      problems=$((problems + 1))
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo "gcp/tests/static/s14-cases holds no failing lock." >&2
    problems=$((problems + 1))
  fi
}

check_root() {
  local dir="$1" lock="$1/.terraform.lock.hcl" data first
  data="$work/data-${dir//\//-}"
  mkdir -p "$data"

  set -- "$dir"/*.tf
  first="$1"
  if [ ! -f "$first" ]; then
    echo "$dir holds no .tf file: an OpenTofu root of the gcp layer is missing (T106 to T108 for gcp/tofu, T110 for gcp/budget)." >&2
    return 1
  fi
  if [ ! -f "$lock" ]; then
    echo "$lock is missing: the lock is versioned, and the init only reads it (ADR-008, condition 7)." >&2
    return 1
  fi

  if ! sandboxed "$data" tofu -chdir="$dir" fmt -check -recursive -diff -no-color; then
    echo "$dir is not formatted: run tofu fmt -recursive in it." >&2
    return 1
  fi

  # -lockfile=readonly verifies every provider against the lock and never
  # writes it; an init that would change the lock fails (research RS-16).
  if ! sandboxed "$data" tofu -chdir="$dir" init -backend=false -lockfile=readonly -input=false -no-color >"$work/init.log" 2>&1; then
    cat "$work/init.log" >&2
    echo "OpenTofu init failed on $dir, backend off and lock read-only." >&2
    return 1
  fi

  sandboxed "$data" tofu -chdir="$dir" validate -no-color
}

check_lock_cases

for dir in $roots; do
  check_root "$dir" || problems=$((problems + 1))
done

if [ "$problems" -gt 0 ]; then
  exit 1
fi
