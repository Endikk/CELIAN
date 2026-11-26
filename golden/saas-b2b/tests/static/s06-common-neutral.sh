#!/usr/bin/env bash
# control: S06
# carries: FR-010; ADR-005, condition 2; ADR-010, condition 1; ADR-015, condition 17
#
# The common layer names no tool and no provider (contracts/layers.md): it
# renders k8s/base and each overlay of k8s/overlays/ with the Kustomize of
# kubectl (research RS-01), then policy/common_neutral.rego reads every
# rendered object. The overlay of the local environment must be there, from
# step 7 on; staging and prod join with steps 9 and 14. The code of the API
# is common too: neither src/ nor k8s/ names the cache engine of the local
# layer or the managed cache of the gcp layer (ADR-015, condition 17).
set -uo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
CDPATH='' cd -- "$root" || exit 2

for tool in conftest kubectl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is not on PATH: S06 renders the common layer with kubectl kustomize and reads it with conftest." >&2
    exit 1
  fi
done
for dir in k8s/base k8s/overlays/local; do
  if [ ! -f "$dir/kustomization.yaml" ]; then
    echo "$dir/kustomization.yaml is missing: the common layer is not written yet (spec 001, T060)." >&2
    exit 1
  fi
done

work="$(mktemp -d)" || exit 2
trap 'rm -rf "${work:?}"' EXIT
rendered=()
for dir in k8s/base k8s/overlays/*/; do
  dir="${dir%/}"
  [ -f "$dir/kustomization.yaml" ] || continue
  name="$(printf '%s' "$dir" | tr '/' '-')"
  if ! kubectl kustomize "$dir" >"$work/$name.yaml" 2>"$work/$name.err"; then
    echo "kubectl kustomize $dir failed:" >&2
    cat "$work/$name.err" >&2
    exit 1
  fi
  rendered+=("$work/$name.yaml")
done

conftest verify --no-color --policy policy --namespace common_neutral || exit 1
conftest test --no-color --combine --policy policy --namespace common_neutral "${rendered[@]}" || exit 1
named="$(grep -r -I -i -l --exclude-dir=bin --exclude-dir=obj -e valkey -e memorystore src k8s || true)"
if [ -n "$named" ]; then
  printf 'These files of the common layer name the cache engine of a target (ADR-015, condition 17):\n%s\n' "$named" >&2
  exit 1
fi
echo "The rendered common layer names no tool and no provider: ${#rendered[@]} render(s)."
