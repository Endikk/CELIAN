#!/usr/bin/env bash
# Installs the tools of `task check` into a directory: Task, conftest,
# OpenTofu and Trivy, from their GitHub releases. Each archive is checked
# against the SHA-256 written in SHA256SUMS, next to this script, before it is
# opened. No third-party GitHub Action is involved (spec 001, T011), and never
# the actions of Trivy (S26).
#
# Usage: tests/tools/install.sh <directory>
# Then put <directory> on PATH. Linux and macOS, amd64 and arm64.
#
# Versions and sums: research RS-09 (Task) and RS-18 (conftest), read on
# 2026-11-23, RS-16 (OpenTofu) and RS-22 (Trivy), read on 2026-11-25, from
# the checksum files that each release publishes. A new version changes the
# constant below and its lines in SHA256SUMS together. For Trivy, [SECU]
# first checks the sigstore signature of the checksum file with cosign
# (research RS-22), then copies the sums.
#
# Renovate proposes the new versions: a custom manager of renovate.json (in
# CELIAN, the one at the root) reads the "# renovate:" comment above each
# constant, under the delay of 7 days. It changes the constant only, and no
# manager updates SHA256SUMS. Its PR fails in CI, this script finding no sum
# for the new archives, until the lines of the new version are written by
# hand in SHA256SUMS, from the checksum file of the release, in the same PR.
set -euo pipefail

# renovate: datasource=github-releases depName=go-task/task
TASK_VERSION="3.54.0"
# renovate: datasource=github-releases depName=open-policy-agent/conftest
CONFTEST_VERSION="0.71.1"
# renovate: datasource=github-releases depName=opentofu/opentofu
TOFU_VERSION="1.13.9"
# renovate: datasource=github-releases depName=aquasecurity/trivy
TRIVY_VERSION="0.76.2"

here="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
sums_file="$here/SHA256SUMS"

die() {
  echo "install.sh: $1" >&2
  exit 1
}

[ "$#" -eq 1 ] || die "usage: tests/tools/install.sh <directory>"
dest="$1"

case "$(uname -s)" in
  Linux) os="linux" ;;
  Darwin) os="darwin" ;;
  *) die "unsupported system $(uname -s): Linux and macOS only." ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch="amd64" ;;
  arm64 | aarch64) arch="arm64" ;;
  *) die "unsupported processor $(uname -m): amd64 and arm64 only." ;;
esac

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

# Expected SHA-256 of release asset $1 ("<owner>/<repo>/<tag>/<file>").
expected_sum() {
  awk -v key="$1" '$2 == key { print $1; found = 1 } END { if (!found) exit 1 }' "$sums_file"
}

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
mkdir -p "$dest"

# Downloads release asset $1, checks it, unpacks it and copies binary $2.
install_binary() {
  local key="$1" binary="$2" owner repo tag file url archive expected actual found count
  owner="$(printf '%s' "$key" | cut -d / -f 1)"
  repo="$(printf '%s' "$key" | cut -d / -f 2)"
  tag="$(printf '%s' "$key" | cut -d / -f 3)"
  file="$(printf '%s' "$key" | cut -d / -f 4)"
  url="https://github.com/$owner/$repo/releases/download/$tag/$file"
  archive="$workdir/$file"

  expected="$(expected_sum "$key")" || die "no SHA-256 for $key in $sums_file."
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    --retry 3 --output "$archive" "$url"
  actual="$(sha256_of "$archive")"
  if [ "$actual" != "$expected" ]; then
    die "SHA-256 mismatch for $file: expected $expected, got $actual. Nothing installed."
  fi

  mkdir -p "$workdir/$binary"
  tar -xzf "$archive" -C "$workdir/$binary"
  count="$(find "$workdir/$binary" -type f -name "$binary" | wc -l | tr -d ' ')"
  [ "$count" = "1" ] || die "expected one file named $binary in $file, found $count."
  found="$(find "$workdir/$binary" -type f -name "$binary")"
  cp "$found" "$dest/$binary"
  chmod 0755 "$dest/$binary"
  echo "Installed $binary from $file, SHA-256 checked."
}

install_binary "go-task/task/v$TASK_VERSION/task_${os}_${arch}.tar.gz" task

case "$os" in
  linux) conftest_os="Linux" ;;
  darwin) conftest_os="Darwin" ;;
esac
case "$arch" in
  amd64) conftest_arch="x86_64" ;;
  arm64) conftest_arch="arm64" ;;
esac
install_binary \
  "open-policy-agent/conftest/v$CONFTEST_VERSION/conftest_${CONFTEST_VERSION}_${conftest_os}_${conftest_arch}.tar.gz" \
  conftest

install_binary "opentofu/opentofu/v$TOFU_VERSION/tofu_${TOFU_VERSION}_${os}_${arch}.tar.gz" tofu

case "$os" in
  linux) trivy_os="Linux" ;;
  darwin) trivy_os="macOS" ;;
esac
case "$arch" in
  amd64) trivy_arch="64bit" ;;
  arm64) trivy_arch="ARM64" ;;
esac
install_binary \
  "aquasecurity/trivy/v$TRIVY_VERSION/trivy_${TRIVY_VERSION}_${trivy_os}-${trivy_arch}.tar.gz" \
  trivy

"$dest/task" --version
"$dest/conftest" --version
"$dest/tofu" version
"$dest/trivy" --version
