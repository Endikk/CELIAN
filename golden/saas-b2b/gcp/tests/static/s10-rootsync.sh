#!/usr/bin/env bash
# control: S10
# carries: FR-012; ADR-010, conditions 3 and 4 and reserve 2 of [FINOPS]; R-31, R-33
#
# RootSync part of S10 (the Flux part is local/tests/static/s10-flux-binding.sh,
# step 12; tasks.md, gap 5). The binding objects of Config Sync, in
# gcp/k8s/bootstrap, applied once by the user and never by Config Sync:
# the tests of package rootsync, then the policy on the render
# (gcp/policy/rootsync.rego): sourceFormat unstructured, roleRefs and no
# cluster-admin, metrics export off, no token, narrow roles. Two more points
# that a policy on one render cannot see:
# - spec.git.dir names a folder of this tree that has a kustomization.yaml,
#   the composition that Config Sync renders;
# - that composition is a Kustomization, not a Component: a Component does not
#   render on its own, and Config Sync renders the folder it is given.
set -uo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
CDPATH='' cd -- "$root" || exit 2

for tool in conftest kubectl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is not on PATH: S10 renders gcp/k8s/bootstrap with the render of the cluster client and reads it with conftest." >&2
    exit 1
  fi
done
if [ ! -f gcp/k8s/bootstrap/kustomization.yaml ]; then
  echo "gcp/k8s/bootstrap/kustomization.yaml is missing: the RootSync of gcp is not written yet (spec 001, T134)." >&2
  exit 1
fi

work="$(mktemp -d)" || exit 2
trap 'rm -rf "${work:?}"' EXIT
kubectl kustomize gcp/k8s/bootstrap >"$work/bootstrap.yaml" 2>"$work/bootstrap.err"
status=$?
if [ "$status" -ne 0 ]; then
  echo "rendering gcp/k8s/bootstrap failed:" >&2
  cat "$work/bootstrap.err" >&2
  exit 1
fi

conftest verify --no-color --policy gcp/policy --namespace rootsync || exit 1
conftest test --no-color --combine --policy gcp/policy --namespace rootsync "$work/bootstrap.yaml" || exit 1

# The folder that the RootSync renders: the line "dir:" of the RootSync, the
# only one of the render.
dir="$(awk '$1 == "dir:" { print $2; exit }' "$work/bootstrap.yaml" | tr -d '"')"
if [ -z "$dir" ] || [ ! -f "$dir/kustomization.yaml" ]; then
  echo "spec.git.dir of the RootSync is '$dir': it has to be a folder of this tree with a kustomization.yaml (the composition gcp/k8s/prod)." >&2
  exit 1
fi
if ! grep -q -E '^kind:[[:space:]]*Kustomization[[:space:]]*$' "$dir/kustomization.yaml"; then
  echo "$dir/kustomization.yaml is not a Kustomization: a Component does not render on its own, and Config Sync renders the folder it is given." >&2
  exit 1
fi
echo "The RootSync of gcp/k8s/bootstrap is bound to narrow roles, renders $dir, and exports no metrics."
