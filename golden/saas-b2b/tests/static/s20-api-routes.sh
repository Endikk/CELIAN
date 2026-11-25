#!/usr/bin/env bash
# control: S20
# carries: FR-009
#
# The API exposes exactly the routes of its contract, no more, no less. Runs
# the tests of policy package api_routes, then the policy on the machine
# description of the API, src/Api/openapi.json (OpenAPI 3.1, kept equal to
# the code by U01, research RS-03), and on the list of contract routes,
# tests/static/s20-contract-routes.yaml. When the golden repo sits in CELIAN,
# at golden/saas-b2b/, the list must also match the headings of the
# contract, specs/001-golden-repo-saas-b2b/contracts/http-api.md; a
# standalone copy (X01) has no such file. Step 4 adds the front part (T029).
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
CDPATH='' cd -- "$root"

routes_file="tests/static/s20-contract-routes.yaml"
inputs="src/Api/openapi.json $routes_file"

if ! command -v conftest >/dev/null 2>&1; then
  echo "conftest is not installed: run tests/tools/install.sh <dir>, then put <dir> on PATH." >&2
  exit 1
fi

for file in $inputs; do
  if [ ! -f "$file" ]; then
    echo "$file is missing: S20 compares the OpenAPI document of the API with the routes of its contract." >&2
    exit 1
  fi
done

# Routes of the list, then of the contract headings (## `GET /api/notes?limit=<n>`),
# query strings left out, one per line, sorted.
listed_routes() {
  sed -n -e 's/^[[:space:]]*-[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*$/\1/p' "$routes_file" | LC_ALL=C sort
}

# shellcheck disable=SC2016 # the backticks are Markdown, not a command substitution
contract_routes() {
  sed -n -e 's/^## `\([A-Z][A-Z]* \/[^`?]*\)[^`]*`[[:space:]]*$/\1/p' "$1" | LC_ALL=C sort
}

celian_root="$(CDPATH='' cd -- "$root/../.." && pwd)"
contract="$celian_root/specs/001-golden-repo-saas-b2b/contracts/http-api.md"
if [ "$celian_root/golden/saas-b2b" = "$root" ] && [ -f "$contract" ]; then
  listed="$(listed_routes)"
  documented="$(contract_routes "$contract")"
  if [ -z "$documented" ]; then
    echo "no route heading found in $contract: S20 reads headings like ## \`GET /api/healthz\`." >&2
    exit 1
  fi
  if [ "$listed" != "$documented" ]; then
    echo "$routes_file does not match the headings of the contract $contract." >&2
    echo "Listed:" >&2
    printf '%s\n' "$listed" | sed -e 's/^/  /' >&2
    echo "In the contract:" >&2
    printf '%s\n' "$documented" | sed -e 's/^/  /' >&2
    exit 1
  fi
fi

conftest verify --no-color --policy policy --namespace api_routes
# shellcheck disable=SC2086 # $inputs is a list of paths without spaces
conftest test --no-color --combine --policy policy --namespace api_routes $inputs
