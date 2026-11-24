#!/usr/bin/env bash
# Checks the renovate.json of CELIAN with the two policy packages of S23,
# shared with the golden repo, as tests/static/s23-renovate.sh checks the
# renovate.json of the golden repo:
# - renovate_delay: the 7 days, the security exception, and the entry of
#   ADR-016 for the registries that Renovate cannot date (ADR-016,
#   condition 2);
# - renovate_rules: the rules that follow golden/saas-b2b/platform.yaml,
#   which the Renovate of CELIAN applies to the files of golden/ (research,
#   RS-17): the postgres major (ADR-012, condition 5), the node image on the
#   Kubernetes minor and kind with its node image (ADR-004, version rule,
#   point 5), Envoy Gateway in one group (ADR-005, updates, point 2), and the
#   custom manager of golden/saas-b2b/tests/tools/install.sh. Both files are
#   checked against the same platform.yaml, so they cannot drift apart.
# Runs the tests of each package, then the package on renovate.json and
# golden/saas-b2b/platform.yaml, then checks the "# renovate:" comments of
# the installer. Called by the pre-commit job of .github/workflows/ci.yml.
#
# Needs conftest on PATH: golden/saas-b2b/tests/tools/install.sh <dir>
# installs it, its archive checked against a SHA-256, then put <dir> on PATH.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"

policy_dir="golden/saas-b2b/policy"
inputs="renovate.json golden/saas-b2b/platform.yaml"
packages="renovate_delay renovate_rules"

if ! command -v conftest >/dev/null 2>&1; then
  echo "conftest is not installed: run golden/saas-b2b/tests/tools/install.sh <dir>, then put <dir> on PATH." >&2
  exit 1
fi

for file in $inputs; do
  if [ ! -f "$file" ]; then
    echo "check-renovate.sh: $file is missing; the update rules of CELIAN are read in renovate.json, and the values they follow in golden/saas-b2b/platform.yaml." >&2
    exit 1
  fi
done

for package in $packages; do
  # conftest passes without a word on a package it does not find (research
  # RS-18). In the golden repo, tests/run-static.sh catches a renamed
  # package; here, check that the policy file still declares it.
  if ! grep -q -x "package $package" "$policy_dir/$package.rego"; then
    echo "check-renovate.sh: $policy_dir/$package.rego does not declare package $package." >&2
    exit 1
  fi
  conftest verify --no-color --policy "$policy_dir" --namespace "$package"
  # shellcheck disable=SC2086 # $inputs is a list of paths without spaces
  conftest test --no-color --combine --policy "$policy_dir" --namespace "$package" $inputs
done

# The versions of the installer of the golden repo, each under the comment
# that the custom manager of renovate.json reads.
bash golden/saas-b2b/tests/tools/check-renovate-comments.sh golden/saas-b2b/tests/tools/install.sh
