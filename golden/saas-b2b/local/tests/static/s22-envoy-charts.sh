#!/usr/bin/env bash
# control: S22
# carries: FR-008; ADR-005, condition 1
#
# The vendored platform keeps the settings of ADR-005 (condition 1):
# local/policy/envoy_render.rego reads the three vendored files with the
# references of local/tasks/local.yml, the controller image and both charts
# of Envoy Gateway, by tag and digest. Every CRD of gateway.networking.k8s.io
# comes from standard-install.yaml, the charts are rendered with crds.* as
# ADR-005 says, every image of the controller render is the controller of
# local/tasks/local.yml, and the render is of the chart that local.yml names:
# a Renovate PR that moves the references without redoing the render fails
# here. Then local/scripts/platform.sh, against a simulated kubectl, refuses
# a controller image that is not the one of the render, before any kubectl
# call; task up passes it ENVOY_GATEWAY_IMAGE of local/tasks/local.yml.
set -uo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
CDPATH='' cd -- "$root" || exit 2

tasks_file="local/tasks/local.yml"
gateway_api="local/vendor/gateway-api/standard-install.yaml"
crds_render="local/vendor/envoy-gateway/gateway-crds-helm.yaml"
helm_render="local/vendor/envoy-gateway/gateway-helm.yaml"
platform_script="local/scripts/platform.sh"
fake_kubectl="local/tests/preflight/fakes/kubectl"

if ! command -v conftest >/dev/null 2>&1; then
  echo "conftest is not installed: run tests/tools/install.sh <dir>, then put <dir> on PATH." >&2
  exit 1
fi
for file in "$gateway_api" "$crds_render" "$helm_render"; do
  if [ ! -f "$file" ]; then
    echo "$file is missing: the platform of task up is not vendored yet (spec 001, T058)." >&2
    exit 1
  fi
done

# var NAME: the value of NAME under vars: of local/tasks/local.yml.
var() {
  awk -v key="$1:" '$1 == key { print $2; exit }' "$tasks_file"
}
controller="$(var ENVOY_GATEWAY_IMAGE)"
helm_chart="$(var ENVOY_GATEWAY_HELM_IMAGE)"
crds_chart="$(var ENVOY_GATEWAY_CRDS_HELM_IMAGE)"
# Each value is checked before it enters the data of the policy, so the
# JSON written below needs no escaping; the policy checks their shape.
for value in "$controller" "$helm_chart" "$crds_chart"; do
  if ! [[ $value =~ ^[A-Za-z0-9./:@_-]*$ ]]; then
    echo "$tasks_file: \"$value\" is not an image reference." >&2
    exit 1
  fi
done

work="$(mktemp -d)" || exit 2
trap 'rm -rf "${work:?}"' EXIT
printf '{"envoy_gateway":{"controller":"%s","helm_chart":"%s","crds_chart":"%s"}}\n' \
  "$controller" "$helm_chart" "$crds_chart" >"$work/references.json"

conftest verify --no-color --policy local/policy --namespace envoy_render || exit 1
conftest test --no-color --combine --policy local/policy --namespace envoy_render \
  --data "$work/references.json" "$gateway_api" "$crds_render" "$helm_render" || exit 1

if [ ! -f "$platform_script" ]; then
  echo "$platform_script is missing: it checks the render before it applies it (spec 001, T061)." >&2
  exit 1
fi
mkdir -p "$work/bin"
ln -s "$root/$fake_kubectl" "$work/bin/kubectl"
other="docker.io/envoyproxy/gateway:v1.9.4@sha256:0000000000000000000000000000000000000000000000000000000000000000"
status=0
out="$(HOME="$work" FAKE_LOG="$work/calls.log" PATH="$work/bin:$PATH" \
  bash "$platform_script" check "$other" 2>&1)" || status=$?
if [ "$status" -eq 0 ]; then
  echo "platform.sh check passed with $other, an image that the render does not run." >&2
  exit 1
fi
case "$out" in
  *"$other"*) ;;
  *)
    echo "platform.sh check refused another controller image without naming it: $out" >&2
    exit 1
    ;;
esac
if [ -s "$work/calls.log" ]; then
  echo "platform.sh check called kubectl: $(tr '\n' ';' <"$work/calls.log")" >&2
  exit 1
fi
echo "The vendored platform keeps the settings of ADR-005 and the release of local/tasks/local.yml."
