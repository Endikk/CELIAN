#!/usr/bin/env bash
# Checks the renovate.json of CELIAN with policy package renovate_delay, the
# delay part of S23, shared with the golden repo (ADR-016, condition 2): the
# 7 days, the security exception, and the entry of ADR-016 for the
# registries that Renovate cannot date. Runs the tests of the package, then
# the package on renovate.json. Called by the pre-commit job of
# .github/workflows/ci.yml.
#
# Needs conftest on PATH: golden/saas-b2b/tests/tools/install.sh <dir>
# installs it, its archive checked against a SHA-256, then put <dir> on PATH.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"

policy_dir="golden/saas-b2b/policy"
package="renovate_delay"

if ! command -v conftest >/dev/null 2>&1; then
  echo "conftest is not installed: run golden/saas-b2b/tests/tools/install.sh <dir>, then put <dir> on PATH." >&2
  exit 1
fi

# conftest passes without a word on a package it does not find (research
# RS-18). In the golden repo, tests/run-static.sh catches a renamed package;
# here, check that the policy file still declares it.
if ! grep -q -x "package $package" "$policy_dir/$package.rego"; then
  echo "check-delay.sh: $policy_dir/$package.rego does not declare package $package." >&2
  exit 1
fi

conftest verify --no-color --policy "$policy_dir" --namespace "$package"
conftest test --no-color --combine --policy "$policy_dir" --namespace "$package" renovate.json
