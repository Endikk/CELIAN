#!/usr/bin/env bash
# control: S05
# carries: FR-002, FR-003, FR-008; ADR-004, conditions 1 and 3, version rule
#
# The kind configuration of the local cluster keeps the API server and every
# published port on 127.0.0.1, and pins each node image by digest
# (local/policy/kind_config.rego); the minor of the node image equals
# kubernetes_minor of platform.yaml (policy/platform_values.rego, shared
# with S21). The host ports of the gateway are the same in the configuration
# and in the tasks, and the node ports of the EnvoyProxy are published
# (local/policy/host_ports.rego; T056, tasks.md, gap 10).
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

# The host ports of the gateway (T056; tasks.md, gap 10; research RS-20):
# one value each, under vars: of local/tasks/local.yml, given to the
# preflight checks of task up, published by local/kind/cluster.yaml, and
# reached by the nodePort of the EnvoyProxy (local/policy/host_ports.rego).
tasks_file="local/tasks/local.yml"
proxy_file="local/platform/envoy-proxy.yaml"
ports=""
for name in GATEWAY_HTTP_PORT GATEWAY_HTTPS_PORT; do
  value="$(awk -v key="$name:" '$1 == key { gsub(/"/, "", $2); print $2; exit }' "$tasks_file")"
  if ! [[ $value =~ ^[0-9]{1,5}$ ]]; then
    echo "$tasks_file: $name is \"$value\"; the host port of the gateway is a number (spec 001, T059)." >&2
    exit 1
  fi
  ports="$ports${ports:+,}$value"
done
preflight_call="- bash local/scripts/preflight.sh '{{.GATEWAY_HTTP_PORT}}' '{{.GATEWAY_HTTPS_PORT}}'"
if ! grep -qF -- "$preflight_call" "$tasks_file"; then
  echo "$tasks_file: task up does not give both host ports of the gateway to the preflight checks: \"$preflight_call\" expected." >&2
  exit 1
fi
if [ ! -f "$proxy_file" ]; then
  echo "$proxy_file is missing: it fixes the node ports of the proxy (spec 001, T059)." >&2
  exit 1
fi
work="$(mktemp -d)"
trap 'rm -rf "${work:?}"' EXIT
printf '{"task_host_ports":[%s]}\n' "$ports" >"$work/ports.json"
conftest verify --no-color --policy local/policy --namespace host_ports
conftest test --no-color --combine --policy local/policy --namespace host_ports \
  --data "$work/ports.json" "$kind_config" "$proxy_file"
