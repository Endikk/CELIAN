#!/usr/bin/env bash
# control: U02
# carries: FR-009, FR-014
#
# Unit tests of the front (src/front/tests/), run in its build image: the
# machine needs Docker, and no Node.js (research RS-06). Builds the test
# stage of src/front/Dockerfile and keeps no image, only the build cache.
# That stage also type-checks and builds the front, then checks the nginx
# configuration of the image under its non-root user. Called by `task test`
# and by the job unit of .github/workflows/golden-saas-b2b.yml.
#
# Usage: tests/unit/u02-front.sh [--update-locks]
# --update-locks writes src/front/package-lock.json after a change of
#   package.json: each package resolved anew must have been published more
#   than 7 days ago (principle VI), and the packages already locked stay.
#   It does not run the tests: run the script again without option, then
#   commit.
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
CDPATH='' cd -- "$root"

dockerfile="src/front/Dockerfile"
context="src/front"

fail() {
  printf 'U02: %s\n' "$1" >&2
  exit 1
}

if ! command -v docker >/dev/null 2>&1; then
  fail "docker is not installed: the unit tests run in the build image of the front (research RS-06)."
fi
if [ ! -f "$dockerfile" ]; then
  fail "$dockerfile is missing: its test stage runs the unit tests of the front (spec 001, T031)."
fi

case "${1:-}" in
  "")
    docker build --file "$dockerfile" --target test --output type=cacheonly --progress plain "$context"
    ;;
  --update-locks)
    out="$(mktemp -d)"
    trap 'rm -rf "$out"' EXIT
    docker build --file "$dockerfile" --target lock-files --output "type=local,dest=$out" --progress plain "$context"
    [ -s "$out/package-lock.json" ] || fail "the build wrote no package-lock.json."
    cp "$out/package-lock.json" src/front/package-lock.json
    echo "src/front/package-lock.json written: check the date of each new package (principle VI), run the tests, then commit it."
    ;;
  *)
    fail "usage: tests/unit/u02-front.sh [--update-locks]"
    ;;
esac
