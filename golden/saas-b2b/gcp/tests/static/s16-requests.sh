#!/usr/bin/env bash
# control: S16
# carries: FR-012; ADR-008, condition 9; R-05
#
# The render of the gcp layer (gcp/k8s/prod) sets `requests` on every pod,
# and holds the ValidatingAdmissionPolicy that refuses a pod without them,
# with its binding on the namespace of the application: the tests of package
# requests, then the policy on the render (gcp/policy/requests.rego). The
# render is made with the Kustomize of kubectl (research RS-01). The
# Deployments of the API and the front join the render with step 9 (T087):
# the policy reads every pod template of it, whatever it holds.
set -uo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
CDPATH='' cd -- "$root" || exit 2

for tool in conftest kubectl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is not on PATH: S16 renders gcp/k8s/prod with kubectl kustomize and reads it with conftest." >&2
    exit 1
  fi
done
if [ ! -f gcp/k8s/prod/kustomization.yaml ]; then
  echo "gcp/k8s/prod/kustomization.yaml is missing: the Kubernetes layer of gcp is not written yet (spec 001, T134)." >&2
  exit 1
fi

work="$(mktemp -d)" || exit 2
trap 'rm -rf "${work:?}"' EXIT
if ! kubectl kustomize gcp/k8s/prod >"$work/gcp.yaml" 2>"$work/gcp.err"; then
  echo "kubectl kustomize gcp/k8s/prod failed:" >&2
  cat "$work/gcp.err" >&2
  exit 1
fi

conftest verify --no-color --policy gcp/policy --namespace requests || exit 1
conftest test --no-color --combine --policy gcp/policy --namespace requests "$work/gcp.yaml" || exit 1
echo "The render of gcp/k8s/prod sets requests on every pod and holds the admission rule."
