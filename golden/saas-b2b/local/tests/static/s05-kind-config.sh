#!/usr/bin/env bash
# control: S05
# carries: FR-003, FR-008; ADR-004, conditions 1 and 3, version rule
#
# The kind configuration of the local cluster keeps the API server and every
# published port on 127.0.0.1, and pins each node image by digest
# (local/policy/kind_config.rego); the minor of the node image equals
# kubernetes_minor of platform.yaml (policy/platform_values.rego, shared
# with S21). Step 7 adds the agreement between the host ports of the
# configuration and those of the tasks (T056).
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
CDPATH='' cd -- "$root"

kind_config="local/kind/cluster.yaml"

if ! command -v conftest >/dev/null 2>&1; then
  echo "conftest is not installed: run tests/tools/install.sh <dir>, then put <dir> on PATH." >&2
  exit 1
fi

if [ ! -f "$kind_config" ]; then
  echo "$kind_config is missing: task up creates the cluster from it (plan, \"Ce que fait task up\", point 2)." >&2
  exit 1
fi

conftest verify --no-color --policy local/policy --namespace kind_config
conftest test --no-color --combine --policy local/policy --namespace kind_config "$kind_config"
conftest test --no-color --combine --policy policy --namespace platform_values platform.yaml "$kind_config"
