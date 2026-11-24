#!/usr/bin/env bash
# control: S01
# carries: FR-008; ADR-004, condition 3; ADR-006, condition 7; ADR-011, condition 4
#
# Every base image of a Dockerfile carries a digest; only images under
# saas-b2b.invalid, built by task up, are exempt. Runs the tests of policy
# package image_digests, then the policy on every Dockerfile of the golden
# repo, of which there must be at least one. Step 9 adds the rendered
# manifests (T086).
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
CDPATH='' cd -- "$root"

if ! command -v conftest >/dev/null 2>&1; then
  echo "conftest is not installed: run tests/tools/install.sh <dir>, then put <dir> on PATH." >&2
  exit 1
fi

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

conftest verify --no-color --policy policy --namespace image_digests
# shellcheck disable=SC2086 # $dockerfiles is a list of paths without spaces
conftest test --no-color --combine --policy policy --namespace image_digests $dockerfiles
