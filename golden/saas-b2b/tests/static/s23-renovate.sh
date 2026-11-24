#!/usr/bin/env bash
# control: S23
# carries: FR-013; constitution, principle VI; ADR-004, version rule, point 5; ADR-005, updates, point 2; ADR-012, condition 5; ADR-016, condition 1
#
# The Renovate configuration of the generated project keeps its update
# rules: 7 days, the security exception, the approval on the Dependency
# Dashboard for the registries that Renovate cannot date (ADR-016), no other
# major for postgres, kind and its node image together, the charts and the
# controller of Envoy Gateway together. Runs the tests of policy packages renovate_delay (the
# delay, which holds for every renovate.json of CELIAN) and renovate_rules
# (the rules that follow platform.yaml, which holds the majors and minors
# they must follow), then both packages on renovate.json and platform.yaml.
# Renovate never reads this file in CELIAN (research RS-17); the validator
# of Renovate reads it in X01.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"

inputs="renovate.json platform.yaml"
packages="renovate_delay renovate_rules"

if ! command -v conftest >/dev/null 2>&1; then
  echo "conftest is not installed: run tests/tools/install.sh <dir>, then put <dir> on PATH." >&2
  exit 1
fi

for file in $inputs; do
  if [ ! -f "$file" ]; then
    echo "$file is missing: S23 reads the update rules of the generated project in renovate.json, and the values they follow in platform.yaml." >&2
    exit 1
  fi
done

# One package per run. conftest says nothing about a package it does not
# find (research RS-18); tests/run-static.sh refuses a policy that no
# control script names, so a misspelt name here fails there.
for package in $packages; do
  conftest verify --no-color --policy policy --namespace "$package"
  # shellcheck disable=SC2086 # $inputs is a list of paths without spaces
  conftest test --no-color --combine --policy policy --namespace "$package" $inputs
done
