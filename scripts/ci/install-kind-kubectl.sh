#!/usr/bin/env bash
# Installs kind and kubectl for the jobs of CELIAN that create a kind
# cluster (.github/workflows/golden-saas-b2b.yml, job e2e-lite), on Linux
# amd64, the runner of the job. Each binary is checked against its SHA-256
# before it is installed:
# - kind: the version and the linux-amd64 sum of the catalog,
#   catalog/kubernetes-cluster.yaml (ADR-004, condition 5): the sum
#   published in the same release protects from corruption, not from a
#   substitution;
# - kubectl: KUBECTL_VERSION and KUBECTL_SHA256 from the environment, pinned
#   in the workflow (spec 001, research RS-18).
# The preflight checks of task up then compare kind with KIND_VERSION of the
# golden repo, and kubectl with the minor of its platform.yaml.
#
# Usage: KUBECTL_VERSION=v1.36.6 KUBECTL_SHA256=<sum> \
#          scripts/ci/install-kind-kubectl.sh <directory>
# Then put <directory> on PATH, before the kind and kubectl of the runner.
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
catalog="$root/catalog/kubernetes-cluster.yaml"

die() {
  echo "install-kind-kubectl.sh: $1" >&2
  exit 1
}

[ "$#" -eq 1 ] || die "usage: scripts/ci/install-kind-kubectl.sh <directory>"
dest="$1"
[ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ] ||
  die "Linux amd64 only, the runner of the job; found $(uname -s) $(uname -m)."
[ -n "${KUBECTL_VERSION:-}" ] && [ -n "${KUBECTL_SHA256:-}" ] ||
  die "KUBECTL_VERSION and KUBECTL_SHA256 must be set; the workflow pins them."
[ -f "$catalog" ] || die "$catalog is missing: it holds the version and the sums of kind."

# The version of the local target and the sum of its linux-amd64 artifact,
# read in the block "local:" of the catalog entry.
read_catalog() {
  awk '
    /^  local:/ { local_block = 1; next }
    /^  [a-z]+:/ { local_block = 0 }
    local_block && /^    version:/ { gsub(/"/, "", $2); print "version " $2 }
    local_block && /- platform: linux-amd64$/ { wanted = 1; next }
    wanted && /sha256:/ { gsub(/"/, "", $2); print "sha256 " $2; wanted = 0 }
  ' "$catalog"
}

kind_version="$(read_catalog | awk '$1 == "version" { print $2; exit }')"
kind_sum="$(read_catalog | awk '$1 == "sha256" { print $2; exit }')"
[[ $kind_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "no kind version in $catalog."
[[ $kind_sum =~ ^[0-9a-f]{64}$ ]] || die "no linux-amd64 SHA-256 of kind in $catalog."

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
mkdir -p "$dest"

# fetch URL SHA256 NAME: downloads URL, checks it, installs it as NAME.
fetch() {
  local url="$1" expected="$2" name="$3" actual
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    --retry 3 --output "$workdir/$name" "$url"
  actual="$(sha256sum "$workdir/$name" | awk '{ print $1 }')"
  [ "$actual" = "$expected" ] ||
    die "SHA-256 mismatch for $name from $url: expected $expected, got $actual. Nothing installed."
  install -m 0755 "$workdir/$name" "$dest/$name"
  echo "Installed $name from $url, SHA-256 checked."
}

fetch "https://github.com/kubernetes-sigs/kind/releases/download/v$kind_version/kind-linux-amd64" \
  "$kind_sum" kind
fetch "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl" "$KUBECTL_SHA256" kubectl

"$dest/kind" version
"$dest/kubectl" version --client
