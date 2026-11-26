#!/usr/bin/env bash
# control: S01
# carries: FR-008; ADR-004, condition 3; ADR-006, condition 7; ADR-011, condition 4
#
# Every base image of a Dockerfile, and every image of a container of the
# rendered manifests, carries a digest; only images under saas-b2b.invalid,
# built by task up, are exempt. Runs the tests of policy package
# image_digests, then the policy on every Dockerfile of the golden repo, of
# which there must be at least one, and on the renders of the local layer,
# made with the Kustomize of kubectl: the common layer alone, and
# local/k8s/lite, the composition that task up applies (T086). The renders
# of the standard and gcp compositions join them with their steps.
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
CDPATH='' cd -- "$root"

for tool in conftest kubectl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is not installed: S01 reads the Dockerfiles and the renders with conftest, and renders with the Kustomize of kubectl (tests/tools/install.sh, scripts/ci/install-kind-kubectl.sh)." >&2
    exit 1
  fi
done

# The names conftest reads with its Dockerfile parser (research RS-18).
dockerfiles=""
while IFS= read -r file; do
  dockerfiles="$dockerfiles ${file#./}"
done < <(find . \( -name .git -o -name node_modules -o -name bin -o -name obj \) -prune -o \
  -type f \( -name Dockerfile -o -name 'Dockerfile.*' -o -name '*.Dockerfile' \) -print | LC_ALL=C sort)

if [ -z "$dockerfiles" ]; then
  echo "no Dockerfile found: the API and front images are built from src/Api/Dockerfile and src/front/Dockerfile (spec 001, T025 and T031)." >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "${work:?}"' EXIT
for render in k8s/overlays/local:common local/k8s/lite:lite; do
  dir="${render%%:*}"
  name="${render##*:}"
  if ! kubectl kustomize "$dir" >"$work/$name.yaml" 2>"$work/$name.err"; then
    echo "kubectl kustomize $dir failed:" >&2
    cat "$work/$name.err" >&2
    exit 1
  fi
done

conftest verify --no-color --policy policy --namespace image_digests
# shellcheck disable=SC2086 # $dockerfiles is a list of paths without spaces
conftest test --no-color --combine --policy policy --namespace image_digests $dockerfiles "$work/common.yaml" "$work/lite.yaml"
