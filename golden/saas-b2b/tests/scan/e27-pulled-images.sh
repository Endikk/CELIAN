#!/usr/bin/env bash
# control: E27
# carries: FR-021, FR-022; spec 001, edge case of the unreachable database; ADR-011, condition 8
#
# The scan of the pulled images of the lite profile, without a cluster (spec
# 001, first PR of step 18, T117):
# 1. with a database repository under .invalid, which resolves to no
#    registry, the scan must fail and say that the database could not be
#    downloaded; it must never pass (spec 001, edge case; research RS-22);
# 2. the scan of the inventory, with the database downloaded in this run:
#    it passes when only reported images carry findings, and fails naming
#    each image and vulnerability at or above the threshold
#    without a valid exception, on the images that block (story 7, scenario 3).
# The second PR of step 18 moves the scan into e2e-lite, built images
# included (T122, T123). Needs the network. Called by the job scan-images of
# .github/workflows/golden-saas-b2b.yml.
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
CDPATH='' cd -- "$root"

scan="tests/scan/scan-images.sh"
unreachable="registry.invalid/aquasec/trivy-db:2"
pass_line="no pulled blocking image carries a vulnerability at or above the threshold without a valid exception; the images built by task up (saas-b2b.invalid) are scanned from the second PR of step 18"

if out="$(bash "$scan" --db-repository "$unreachable" lite 2>&1)"; then
  printf '%s\n' "$out" >&2
  echo "E27: the scan passed with the database repository $unreachable, which resolves nowhere: it must fail." >&2
  exit 1
fi
if printf '%s\n' "$out" | grep -q -F "$pass_line" ||
  ! printf '%s\n' "$out" | grep -q -F 'vulnerability database could not be downloaded'; then
  printf '%s\n' "$out" >&2
  echo "E27: without a database, the scan fails without saying that the database could not be downloaded." >&2
  exit 1
fi
echo "E27: without a database, the scan fails and says so."

bash "$scan" lite
