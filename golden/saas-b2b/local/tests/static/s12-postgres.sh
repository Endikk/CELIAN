#!/usr/bin/env bash
# control: S12
# carries: FR-017; ADR-012, conditions 1, 2 and 8; R-20, R-35
#
# Postgres of the local layer keeps the conditions of ADR-012, once
# rendered: local/policy/postgres.rego reads the render of local/k8s/lite,
# the composition that task up applies, and the render of the common layer
# alone, k8s/overlays/local. UID 999, runAsNonRoot, capabilities dropped,
# seccomp, no service account token, a read-only root filesystem; the
# superuser from the files of db-superuser, scram-sha-256 for initdb, no
# trust anywhere; db-superuser mounted by Postgres alone, and named nowhere
# in the common layer; the data under /var/lib/postgresql. Runs the tests of
# the policy, then the policy on both renders, made with the Kustomize of
# kubectl, as S06 does (research RS-01). The major of the image is S21's.
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
CDPATH='' cd -- "$root"

composition="local/k8s/lite"
common="k8s/overlays/local"

for tool in conftest kubectl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is not installed: S12 renders the layers with the Kustomize of kubectl and reads them with conftest (tests/tools/install.sh)." >&2
    exit 1
  fi
done
for dir in "$composition" "$common"; do
  if [ ! -f "$dir/kustomization.yaml" ]; then
    echo "$dir/kustomization.yaml is missing: Postgres of the local layer is not written yet (spec 001, T069 and T070)." >&2
    exit 1
  fi
done

work="$(mktemp -d)" || exit 2
trap 'rm -rf "${work:?}"' EXIT
kubectl kustomize "$composition" >"$work/lite.yaml"
kubectl kustomize "$common" >"$work/common.yaml"

conftest verify --no-color --policy local/policy --namespace postgres
conftest test --no-color --combine --policy local/policy --namespace postgres "$work/lite.yaml" "$work/common.yaml"
