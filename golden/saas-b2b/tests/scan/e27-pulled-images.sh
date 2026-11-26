#!/usr/bin/env bash
# control: E27
# carries: FR-020, FR-021, FR-022; spec 001, edge case of the unreachable database; ADR-011, condition 8
#
# The scan of the images of the lite profile, without a cluster (spec 001,
# first and second PR of step 18, T117): the pulled images, and the images
# that the project builds, the API and the front. The file keeps the name of
# the control, E27, which the plan gives to the scan of the inventory.
# 1. with a database repository under .invalid, which resolves to no
#    registry, the scan must fail and say that the database could not be
#    downloaded; it must never pass (spec 001, edge case; research RS-22);
# 2. the scan of the inventory, for the platform given, with the database
#    downloaded in this run: it builds the two images, keeps their CycloneDX
#    SBOM in the directory given, and passes when only reported images carry
#    findings. It fails naming each image and vulnerability at or above the
#    threshold without a valid exception, on the images that block (story 7,
#    scenario 3), and on a report that is empty or of another platform.
# Each platform is scanned by a job of its own: the arguments go to
# tests/scan/scan-images.sh as they are. E25 and E26, which read the images
# that run in the cluster, and the move of the scan into e2e-lite (T119 to
# T123) are not part of this control yet. Needs the network and docker. Called
# by the jobs scan-images and scan-images-arm64 of
# .github/workflows/golden-saas-b2b.yml.
#
# Usage: tests/scan/e27-pulled-images.sh [--platform linux/amd64|linux/arm64] --sbom-dir <directory>
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
CDPATH='' cd -- "$root"

scan="tests/scan/scan-images.sh"
unreachable="registry.invalid/aquasec/trivy-db:2"
pass_line="no blocking image carries a vulnerability at or above the threshold without a valid exception"

if out="$(bash "$scan" --db-repository "$unreachable" "$@" lite 2>&1)"; then
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

bash "$scan" "$@" lite
