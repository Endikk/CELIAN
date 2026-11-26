#!/usr/bin/env bash
# Installs kind and kubectl for the jobs of CELIAN that create a kind
# cluster (.github/workflows/golden-saas-b2b.yml, job e2e-lite) or that render
# a Kustomization (the scan of the images), on Linux amd64, the runner of
# most jobs, or on Linux arm64, the runner of the job that scans the arm64
# variant of the images. Each binary is checked against its SHA-256 before it
# is installed:
# - kind: the version and the linux-amd64 or linux-arm64 sum of the catalog,
#   catalog/kubernetes-cluster.yaml (ADR-004, condition 5): the sum
#   published in the same release protects from corruption, not from a
#   substitution;
# - kubectl: KUBECTL_VERSION from the environment, and KUBECTL_SHA256 on
#   amd64 or KUBECTL_SHA256_ARM64 on arm64, pinned in the workflow (spec 001,
#   research RS-18). Each is the content of kubectl.sha256 beside the binary
#   on dl.k8s.io.
# The preflight checks of task up then compare kind with KIND_VERSION of the
# golden repo, and kubectl with the minor of its platform.yaml.
#
# Usage: KUBECTL_VERSION=v1.36.6 KUBECTL_SHA256=<sum> KUBECTL_SHA256_ARM64=<sum> \
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
[ "$(uname -s)" = Linux ] || die "Linux only, the runner of the job; found $(uname -s) $(uname -m)."
case "$(uname -m)" in
  x86_64)
    arch="amd64"
    kubectl_sum="${KUBECTL_SHA256:-}"
    ;;
  aarch64 | arm64)
    arch="arm64"
    kubectl_sum="${KUBECTL_SHA256_ARM64:-}"
    ;;
  *) die "amd64 and arm64 only, the runners of the jobs; found $(uname -s) $(uname -m)." ;;
esac
[ -n "${KUBECTL_VERSION:-}" ] && [ -n "$kubectl_sum" ] ||
  die "KUBECTL_VERSION and the SHA-256 of kubectl for linux-$arch (KUBECTL_SHA256 on amd64, KUBECTL_SHA256_ARM64 on arm64) must be set; the workflow pins them."
[ -f "$catalog" ] || die "$catalog is missing: it holds the version and the sums of kind."

# The version of the local target and the sum of its linux-$arch artifact,
# read in the block "local:" of the catalog entry.
read_catalog() {
  awk -v platform="linux-$arch" '
    /^  local:/ { local_block = 1; next }
    /^  [a-z]+:/ { local_block = 0 }
    local_block && /^    version:/ { gsub(/"/, "", $2); print "version " $2 }
    local_block && $0 ~ ("- platform: " platform "$") { wanted = 1; next }
    wanted && /sha256:/ { gsub(/"/, "", $2); print "sha256 " $2; wanted = 0 }
  ' "$catalog"
}

kind_version="$(read_catalog | awk '$1 == "version" { print $2; exit }')"
kind_sum="$(read_catalog | awk '$1 == "sha256" { print $2; exit }')"
[[ $kind_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "no kind version in $catalog."
[[ $kind_sum =~ ^[0-9a-f]{64}$ ]] || die "no linux-$arch SHA-256 of kind in $catalog."

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

fetch "https://github.com/kubernetes-sigs/kind/releases/download/v$kind_version/kind-linux-$arch" \
  "$kind_sum" kind
fetch "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/$arch/kubectl" "$kubectl_sum" kubectl

"$dest/kind" version
"$dest/kubectl" version --client
