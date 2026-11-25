#!/usr/bin/env bash
# control: U01
# carries: FR-009, FR-014
#
# Unit tests of the API (src/Api.Tests/), run in its build image: the machine
# needs Docker, and no .NET SDK (research RS-06). Builds the test stage of
# src/Api/Dockerfile and keeps no image, only the build cache. Called by
# `task test` and by the job unit of .github/workflows/golden-saas-b2b.yml.
#
# Usage: tests/unit/u01-api.sh [--update-openapi | --update-locks]
# --update-openapi writes src/Api/openapi.json, the OpenAPI document that S20
#   reads, from the code of the API;
# --update-locks resolves the packages anew and writes the packages.lock.json
#   of both projects, after a change of their package references.
# Neither runs the tests: run the script again without option, then commit.
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
CDPATH='' cd -- "$root"

dockerfile="src/Api/Dockerfile"
context="src"

fail() {
  printf 'U01: %s\n' "$1" >&2
  exit 1
}

if ! command -v docker >/dev/null 2>&1; then
  fail "docker is not installed: the unit tests run in the build image of the API (research RS-06)."
fi
if [ ! -f "$dockerfile" ]; then
  fail "$dockerfile is missing: its test stage runs the unit tests of the API (spec 001, T025)."
fi

# Builds stage $1 of the Dockerfile and copies its files into directory $2.
export_stage() {
  docker build --file "$dockerfile" --target "$1" --output "type=local,dest=$2" --progress plain "$context"
}

case "${1:-}" in
  "")
    docker build --file "$dockerfile" --target test --output type=cacheonly --progress plain "$context"
    ;;
  --update-openapi)
    out="$(mktemp -d)"
    trap 'rm -rf "$out"' EXIT
    export_stage openapi-document "$out"
    [ -s "$out/openapi.json" ] || fail "the build wrote no openapi.json."
    cp "$out/openapi.json" src/Api/openapi.json
    echo "src/Api/openapi.json written from the API: review it, run the tests, then commit it."
    ;;
  --update-locks)
    out="$(mktemp -d)"
    trap 'rm -rf "$out"' EXIT
    export_stage lock-files "$out"
    for project in Api Api.Tests; do
      [ -s "$out/$project/packages.lock.json" ] || fail "the build wrote no $project/packages.lock.json."
      cp "$out/$project/packages.lock.json" "src/$project/packages.lock.json"
      # NuGet ends the file without a line break, which the end-of-file hook adds.
      if [ -n "$(tail -c 1 "src/$project/packages.lock.json")" ]; then
        printf '\n' >> "src/$project/packages.lock.json"
      fi
    done
    echo "packages.lock.json written for Api and Api.Tests: check the date of each new package (principle VI), run the tests, then commit them."
    ;;
  *)
    fail "usage: tests/unit/u01-api.sh [--update-openapi | --update-locks]"
    ;;
esac
