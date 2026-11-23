#!/usr/bin/env bash
# control: S21
# carries: FR-010, FR-017; ADR-004, version rule; ADR-012, condition 5
#
# The Kubernetes minor and the Postgres major have one value each, in
# platform.yaml, and every file that repeats them agrees with it. Runs the
# tests of policy package platform_values, then the policy on the real files.
# Step 1 gives it platform.yaml alone; T041, T065 and T105 add the kind
# configuration, the Postgres manifests and the OpenTofu layer to "inputs".
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"

inputs="platform.yaml"

if ! command -v conftest >/dev/null 2>&1; then
  echo "conftest is not installed: run tests/tools/install.sh <dir>, then put <dir> on PATH." >&2
  exit 1
fi

for file in $inputs; do
  if [ ! -f "$file" ]; then
    echo "$file is missing: it holds the values shared by both layers (data-model, \"Valeurs partagées\")." >&2
    exit 1
  fi
done

conftest verify --no-color --policy policy --namespace platform_values
# shellcheck disable=SC2086 # $inputs is a list of paths without spaces
conftest test --no-color --combine --policy policy --namespace platform_values $inputs
