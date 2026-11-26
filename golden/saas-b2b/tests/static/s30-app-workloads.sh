#!/usr/bin/env bash
# control: S30
# carries: FR-009, FR-010; ADR-007, condition 5; ADR-012, condition 9
#
# The Deployments and Services of the API and the front, in the common layer
# (spec 001, T087; tasks.md, gap 148): restricted profile with a read-only
# root filesystem, bounded emptyDir, requests and limits, probes on the paths
# of the contract, Secrets by mounted files, the label that the
# NetworkPolicies admit, routes that reach their Services
# (policy/app_workloads.rego). Runs the tests of the policy, then the policy
# on the render of the common layer, k8s/overlays/local, made with the
# Kustomize of kubectl.
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
CDPATH='' cd -- "$root"

for tool in conftest kubectl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is not installed: S30 renders the common layer with the Kustomize of kubectl and reads it with conftest (tests/tools/install.sh, scripts/ci/install-kind-kubectl.sh)." >&2
    exit 1
  fi
done

work="$(mktemp -d)"
trap 'rm -rf "${work:?}"' EXIT
if ! kubectl kustomize k8s/overlays/local >"$work/common.yaml" 2>"$work/render.err"; then
  echo "kubectl kustomize k8s/overlays/local failed:" >&2
  cat "$work/render.err" >&2
  exit 1
fi

conftest verify --no-color --policy policy --namespace app_workloads
conftest test --no-color --combine --policy policy --namespace app_workloads "$work/common.yaml"
