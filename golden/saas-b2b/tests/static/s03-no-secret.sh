#!/usr/bin/env bash
# control: S03
# carries: FR-004; ADR-006, condition 1; ADR-007, condition 1
#
# No Secret is versioned: policy/no_secret.rego reads every YAML and JSON
# file of the golden repo, the vendored manifests and the build outputs
# aside, and refuses an object of kind Secret and a secretGenerator. Runs the
# tests of the policy, then the policy on the files. The Secrets of the
# local target are born on the machine, through a pipe, by task up
# (local/scripts/secrets.sh; ADR-007, condition 1).
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
CDPATH='' cd -- "$root"

if ! command -v conftest >/dev/null 2>&1; then
  echo "conftest is not installed: run tests/tools/install.sh <dir>, then put <dir> on PATH." >&2
  exit 1
fi

# The files read: every *.yaml, *.yml and *.json of the golden repo, but
# under .git, node_modules and the .NET build outputs. The vendored
# manifests of local/vendor/ are read too: a release of Envoy Gateway that
# ships a Secret shows here.
files=()
while IFS= read -r file; do
  files+=("$file")
done < <(find . \( -name .git -o -name node_modules -o -name bin -o -name obj \) -prune -o \
  -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.json' \) -print | LC_ALL=C sort)
if [ "${#files[@]}" -eq 0 ]; then
  echo "no YAML nor JSON file found in the golden repo: S03 has nothing to read." >&2
  exit 1
fi

conftest verify --no-color --policy policy --namespace no_secret
conftest test --no-color --combine --policy policy --namespace no_secret "${files[@]}"
