#!/usr/bin/env bash
# Installs Helm for the job that redoes the render of Envoy Gateway
# (.github/workflows/golden-saas-b2b.yml, job envoy-render), on Linux amd64,
# the runner of the job. The archive is checked against its SHA-256 before
# anything is extracted, as scripts/ci/install-kind-kubectl.sh does for
# kubectl: HELM_VERSION and HELM_SHA256 come from the environment, pinned in
# the workflow. The sum is the one of helm-<version>-linux-amd64.tar.gz.sha256sum
# on get.helm.sh, the same as in the notes of the release on GitHub.
#
# Usage: HELM_VERSION=v4.3.2 HELM_SHA256=<sum> scripts/ci/install-helm.sh <directory>
# Then put <directory> on PATH, before the helm of the runner.
set -euo pipefail

die() {
  echo "install-helm.sh: $1" >&2
  exit 1
}

[ "$#" -eq 1 ] || die "usage: scripts/ci/install-helm.sh <directory>"
dest="$1"
[ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ] ||
  die "Linux amd64 only, the runner of the job; found $(uname -s) $(uname -m)."
[ -n "${HELM_VERSION:-}" ] && [ -n "${HELM_SHA256:-}" ] ||
  die "HELM_VERSION and HELM_SHA256 must be set; the workflow pins them."
[[ $HELM_VERSION =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "HELM_VERSION \"$HELM_VERSION\" is not vX.Y.Z."
[[ $HELM_SHA256 =~ ^[0-9a-f]{64}$ ]] || die "HELM_SHA256 is not a SHA-256."

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
mkdir -p "$dest"

archive="helm-$HELM_VERSION-linux-amd64.tar.gz"
url="https://get.helm.sh/$archive"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  --retry 3 --output "$workdir/$archive" "$url"
actual="$(sha256sum "$workdir/$archive" | awk '{ print $1 }')"
[ "$actual" = "$HELM_SHA256" ] ||
  die "SHA-256 mismatch for $archive from $url: expected $HELM_SHA256, got $actual. Nothing installed."

# Only the binary is extracted, once the sum is right.
tar -xzf "$workdir/$archive" -C "$workdir" linux-amd64/helm
install -m 0755 "$workdir/linux-amd64/helm" "$dest/helm"
echo "Installed helm from $url, SHA-256 checked."

"$dest/helm" version --short
