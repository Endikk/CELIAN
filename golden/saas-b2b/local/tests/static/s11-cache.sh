#!/usr/bin/env bash
# control: S11
# carries: FR-004; ADR-006, condition 2; ADR-015, conditions 3 to 6, 10 and 15
#
# The cache of the local layer keeps its password out of every command line
# and every environment of the server, and runs as ADR-015 wants it: it
# renders local/data/cache with the Kustomize of kubectl, as task up applies
# it, so that the script of the init container is read from its ConfigMap,
# then local/policy/cache_layer.rego reads the render and the probe Job of
# task up, local/data/cache/probe/job.yaml. The pre-commit hook passes the
# init script to shellcheck in POSIX sh, the shell of the image. The line
# of the image against platform.yaml is S21's.
set -uo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
CDPATH='' cd -- "$root" || exit 2

layer="local/data/cache"
probe="$layer/probe/job.yaml"
script="$layer/init/write-config.sh"

for tool in conftest kubectl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is not on PATH: S11 renders the cache layer with kubectl kustomize and reads it with conftest." >&2
    exit 1
  fi
done
for file in "$layer/kustomization.yaml" "$probe" "$script"; do
  if [ ! -f "$file" ]; then
    echo "$file is missing: the cache layer of ADR-015 is not written yet (spec 001, T079)." >&2
    exit 1
  fi
done

work="$(mktemp -d)" || exit 2
trap 'rm -rf "${work:?}"' EXIT
if ! kubectl kustomize "$layer" >"$work/cache.yaml" 2>"$work/cache.err"; then
  echo "kubectl kustomize $layer failed:" >&2
  cat "$work/cache.err" >&2
  exit 1
fi

conftest verify --no-color --policy local/policy --namespace cache_layer || exit 1
conftest test --no-color --combine --policy local/policy --namespace cache_layer "$work/cache.yaml" "$probe" || exit 1

echo "The cache layer keeps its password out of the command lines and of the environment of the server, as ADR-015 wants it."
