#!/usr/bin/env bash
# control: S31
# carries: FR-010; ADR-007, condition 5; ADR-012; ADR-015, condition 7; research RS-16
#
# The values that the user writes into gcp/k8s/values/ after the first apply
# (the host and the CA of the database, the host of the cache, the project of
# Secret Manager), and the producer of db-auth: the tests of package
# gcp_values, then the policy on the render of gcp/k8s/prod
# (gcp/policy/gcp_values.rego). Placeholders under .invalid, an empty CA
# bundle and the word PROJECT_ID pass: they fail closed at run time, and the
# apply is not part of this repository. Reports each key and path that the
# policy reads, so that a review of the pull request that carries the real
# values knows what to look at (research RS-16).
set -uo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
CDPATH='' cd -- "$root" || exit 2

for tool in conftest kubectl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is not on PATH: S31 renders gcp/k8s/prod with kubectl kustomize and reads it with conftest." >&2
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

conftest verify --no-color --policy gcp/policy --namespace gcp_values || exit 1
conftest test --no-color --combine --policy gcp/policy --namespace gcp_values "$work/gcp.yaml" || exit 1

# The values of the repository are still the placeholders until the first
# apply: say so, without failing (the apply belongs to the user, principle X).
pending=""
if grep -q -E '^[[:space:]]+(DATABASE|CACHE)_HOST:[[:space:]]+.*\.invalid[[:space:]]*$' "$work/gcp.yaml"; then
  pending="$pending the hosts of the database and of the cache,"
fi
if grep -q -E 'projects/PROJECT_ID/' "$work/gcp.yaml"; then
  pending="$pending the project of Secret Manager,"
fi
if grep -q -E '(database|cache)-ca\.pem: ""' "$work/gcp.yaml"; then
  pending="$pending the CA bundles,"
fi
if [ -n "$pending" ]; then
  echo "Placeholders still in gcp/k8s/values/ (they are written after the first apply, principle X):${pending%,}."
fi
echo "The values and the producer of db-auth in the render of gcp/k8s/prod are well formed."
