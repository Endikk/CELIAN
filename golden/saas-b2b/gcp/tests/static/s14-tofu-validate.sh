#!/usr/bin/env bash
# control: S14
# carries: FR-011; ADR-008, condition 7; constitution, principle X
#
# The OpenTofu root of the gcp layer, gcp/tofu/, is formatted, initializes
# against its versioned lock without changing it, and validates, without any
# backend or credential (spec 001, plan, S14). `task gcp:validate` runs this
# script; `task check` runs it through tests/run-static.sh.
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

dir="gcp/tofu"
lock="$dir/.terraform.lock.hcl"

if ! command -v tofu >/dev/null 2>&1; then
  echo "tofu is not installed: run tests/tools/install.sh <dir>, then put <dir> on PATH." >&2
  exit 1
fi

set -- "$dir"/*.tf
if [ ! -f "$1" ]; then
  echo "$dir holds no .tf file: the OpenTofu root of the gcp layer is missing (T106 to T108)." >&2
  exit 1
fi
if [ ! -f "$lock" ]; then
  echo "$lock is missing: the lock is versioned, and the init only reads it (ADR-008, condition 7)." >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/home" "$work/data"

# Runs its arguments with PATH, a temporary HOME and the data directory only.
# TF_IN_AUTOMATION keeps OpenTofu from suggesting the next command.
sandboxed() {
  env -i PATH="$PATH" HOME="$work/home" TF_DATA_DIR="$work/data" TF_IN_AUTOMATION=1 "$@"
}

if ! sandboxed tofu -chdir="$dir" fmt -check -recursive -diff -no-color; then
  echo "$dir is not formatted: run tofu fmt -recursive in it." >&2
  exit 1
fi

# -lockfile=readonly verifies every provider against the lock and never
# writes it; an init that would change the lock fails (research RS-16).
sandboxed tofu -chdir="$dir" init -backend=false -lockfile=readonly -input=false -no-color >"$work/init.log" 2>&1 || {
  cat "$work/init.log" >&2
  echo "tofu init failed on $dir, backend off and lock read-only." >&2
  exit 1
}

sandboxed tofu -chdir="$dir" validate -no-color
