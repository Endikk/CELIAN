#!/usr/bin/env bash
# control: S07
# carries: FR-008, FR-010; ADR-005, condition 5; ADR-007, condition 5; ADR-010, condition 1
#
# Parity (spec 001, T086 and T130; contracts/layers.md, "Règle de
# parité"). The common layer rendered alone, k8s/overlays/local, is found
# again in the render of local/k8s/lite, which task up applies, except for
# spec.gatewayClassName and the hostnames of the routes, which a target
# sets; the objects that the local render adds come from files of the local
# layer; one Gateway per render; the references to app-config and to the
# Secrets are those of the contracts; no render sets ASPNETCORE_ENVIRONMENT
# nor DOTNET_ENVIRONMENT to Development; the HTTPRoutes name localhost
# (policy/layer_parity.rego). The gcp part follows, when gcp/k8s/ is there (a
# project rendered for the local target alone has none): step 14 joined it, the
# two parts are one control (tasks.md, gap 176). It is described below.
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

# --- gcp part (spec 001, T130; contracts/layers.md, "Règle de parité") ------------
# The render of the gcp layer holds the common layer as it is, and what it adds
# comes from the gcp layer (gcp/policy/gcp_parity.rego). Four renders:
# - gcp-common.yaml: k8s/overlays/prod, the common layer alone;
# - gcp.yaml: gcp/k8s/prod, the same overlay with the component of the gcp
#   target;
# - gcp-layer.yaml: the files of the gcp layer as written, gcp/k8s/component/
#   and the renders of gcp/k8s/values/ and gcp/k8s/admission/, to tell what
#   comes from the layer;
# - gcp-bootstrap.yaml: gcp/k8s/bootstrap, whose namespace is the common one and
#   which holds the admission objects that Config Sync only updates.
# The policy fails on a difference other than spec.gatewayClassName, on an object
# that comes from nowhere, on a second Gateway, and on a Secret or a ConfigMap that
# a pod of the common layer reads and the gcp layer does not produce. A Secret
# with a producer to come raises a warning, listed in the policy with its reason.
# A project rendered for the local target alone has no gcp/k8s/ and skips it.
if [ -d gcp/k8s ]; then
  for dir in k8s/overlays/prod gcp/k8s/prod gcp/k8s/values gcp/k8s/admission gcp/k8s/bootstrap; do
    if [ ! -f "$dir/kustomization.yaml" ]; then
      echo "$dir/kustomization.yaml is missing: the prod overlay (T133) or the gcp layer (T134) is not written." >&2
      exit 1
    fi
  done
  render k8s/overlays/prod "$work/gcp-common.yaml"
  render gcp/k8s/prod "$work/gcp.yaml"
  render gcp/k8s/bootstrap "$work/gcp-bootstrap.yaml"
  render gcp/k8s/values "$work/gcp-values.yaml"
  render gcp/k8s/admission "$work/gcp-admission.yaml"
  # Every file of the component but its kustomization.yaml, then the two renders.
  : >"$work/gcp-layer.yaml"
  for file in gcp/k8s/component/*.yaml; do
    [ -f "$file" ] || continue
    [ "$(basename "$file")" = kustomization.yaml ] && continue
    {
      printf -- '---\n'
      cat "$file"
      printf '\n'
    } >>"$work/gcp-layer.yaml"
  done
  {
    printf -- '---\n'
    cat "$work/gcp-values.yaml"
    printf -- '---\n'
    cat "$work/gcp-admission.yaml"
  } >>"$work/gcp-layer.yaml"

  conftest verify --no-color --policy gcp/policy --namespace gcp_parity
  conftest test --no-color --combine --policy gcp/policy --namespace gcp_parity \
    "$work/gcp-common.yaml" "$work/gcp.yaml" "$work/gcp-layer.yaml" "$work/gcp-bootstrap.yaml"
fi
