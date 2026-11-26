#!/usr/bin/env bash
# control: S07
# carries: FR-010; ADR-005, condition 5; ADR-007, condition 5
#
# gcp part of S07 (contracts/layers.md, "Règle de parité"; tasks.md, gap 163).
# The local part, tests/static/s07-parity.sh, is written with step 9 (T086);
# the two meet when that file lands, and the DSI decides whether they merge.
#
# Four renders with the Kustomize of kubectl (research RS-01), compared by
# gcp/policy/gcp_parity.rego:
# - common.yaml: k8s/overlays/prod, the common layer alone;
# - gcp.yaml: gcp/k8s/prod, the same overlay with the component of the gcp
#   target;
# - layer.yaml: the files of the gcp layer as written, gcp/k8s/component/
#   and the renders of gcp/k8s/values/ and gcp/k8s/admission/, to tell what
#   comes from the layer;
# - bootstrap.yaml: gcp/k8s/bootstrap, whose namespace is the common one and
#   which holds the admission objects that Config Sync only updates.
# The policy fails on a difference other than spec.gatewayClassName, on an
# object that comes from nowhere, on a second Gateway, and on a Secret or a
# ConfigMap that a pod of the common layer reads and the gcp layer does not
# produce. A Secret with a producer to come raises a warning, listed in the
# policy with its reason.
set -uo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
CDPATH='' cd -- "$root" || exit 2

for tool in conftest kubectl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is not on PATH: S07 renders the layers with the render of the cluster client and compares them with conftest." >&2
    exit 1
  fi
done
for dir in k8s/overlays/prod gcp/k8s/prod gcp/k8s/values gcp/k8s/admission gcp/k8s/bootstrap; do
  if [ ! -f "$dir/kustomization.yaml" ]; then
    echo "$dir/kustomization.yaml is missing: the prod overlay (T133) or the gcp layer (T134) is not written yet." >&2
    exit 1
  fi
done

work="$(mktemp -d)" || exit 2
trap 'rm -rf "${work:?}"' EXIT

render() {
  # $1 folder, $2 output file
  kubectl kustomize "$1" >"$2" 2>"$work/render.err"
  status=$?
  if [ "$status" -ne 0 ]; then
    echo "rendering $1 failed:" >&2
    cat "$work/render.err" >&2
    exit 1
  fi
}

render k8s/overlays/prod "$work/common.yaml"
render gcp/k8s/prod "$work/gcp.yaml"
render gcp/k8s/bootstrap "$work/bootstrap.yaml"

# The objects of the layer as written: every file of the component but its
# kustomization.yaml, then the render of the values folder.
: >"$work/layer.yaml"
for file in gcp/k8s/component/*.yaml; do
  [ -f "$file" ] || continue
  [ "$(basename "$file")" = kustomization.yaml ] && continue
  { printf -- '---\n'; cat "$file"; printf '\n'; } >>"$work/layer.yaml"
done
render gcp/k8s/values "$work/values.yaml"
render gcp/k8s/admission "$work/admission.yaml"
{ printf -- '---\n'; cat "$work/values.yaml"; printf -- '---\n'; cat "$work/admission.yaml"; } >>"$work/layer.yaml"

conftest verify --no-color --policy gcp/policy --namespace gcp_parity || exit 1
conftest test --no-color --combine --policy gcp/policy --namespace gcp_parity \
  "$work/common.yaml" "$work/gcp.yaml" "$work/layer.yaml" "$work/bootstrap.yaml" || exit 1
echo "The render of gcp holds the common layer as it is, but for the class of the Gateway."
