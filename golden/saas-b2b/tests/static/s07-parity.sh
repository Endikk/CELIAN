#!/usr/bin/env bash
# control: S07
# carries: FR-008, FR-010; ADR-005, condition 5; ADR-007, condition 5; ADR-010, condition 1
#
# Parity, local part (spec 001, T086; contracts/layers.md, "Règle de
# parité"). The common layer rendered alone, k8s/overlays/local, is found
# again in the render of local/k8s/lite, which task up applies, except for
# spec.gatewayClassName and the hostnames of the routes, which a target
# sets; the objects that the local render adds come from files of the local
# layer; one Gateway per render; the references to app-config and to the
# Secrets are those of the contracts; no render sets ASPNETCORE_ENVIRONMENT
# nor DOTNET_ENVIRONMENT to Development; the HTTPRoutes name localhost
# (policy/layer_parity.rego). The gcp render joins the comparison with step
# 14, which makes the parity complete.
#
# The renders come from the Kustomize of kubectl, as in S06 and S12
# (research RS-01). The objects of the local layer on their own are the
# render of local/data and of local/data/cache, and the files that
# local/k8s/component/ lists beside its Kustomization.
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
CDPATH='' cd -- "$root"

for tool in conftest kubectl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is not installed: S07 renders the layers with the Kustomize of kubectl and reads them with conftest (tests/tools/install.sh, scripts/ci/install-kind-kubectl.sh)." >&2
    exit 1
  fi
done

common="k8s/overlays/local"
composition="local/k8s/lite"
component="local/k8s/component"
app_config="$component/app-config.yaml"
for file in "$common/kustomization.yaml" "$composition/kustomization.yaml" "$app_config"; do
  if [ ! -f "$file" ]; then
    echo "$file is missing: the local part of S07 compares the local render with the common layer, and the local app-config is written at step 9 (spec 001, T087)." >&2
    exit 1
  fi
done

work="$(mktemp -d)"
trap 'rm -rf "${work:?}"' EXIT
render() {
  if ! kubectl kustomize "$1" >"$2" 2>"$work/render.err"; then
    echo "kubectl kustomize $1 failed:" >&2
    cat "$work/render.err" >&2
    exit 1
  fi
}
render "$common" "$work/common.yaml"
render "$composition" "$work/lite.yaml"
render local/data "$work/data.yaml"
render local/data/cache "$work/cache.yaml"
{
  cat "$work/data.yaml"
  printf '%s\n' '---'
  cat "$work/cache.yaml"
  printf '%s\n' '---'
  cat "$app_config"
} >"$work/sources.yaml"

conftest verify --no-color --policy policy --namespace layer_parity
conftest test --no-color --combine --policy policy --namespace layer_parity \
  "$work/common.yaml" "$work/lite.yaml" "$work/sources.yaml"
