#!/usr/bin/env bash
# Test cases of S18 (tests/static/s18-readme.sh), run by it when it has no
# argument. Each case copies the README of the golden repo, with the files
# that S18 reads it against, into a folder of its own, breaks one thing, and
# expects S18 to fail with the message that names it. The unchanged README
# comes first and must pass: a case that fails for another reason proves
# nothing.
set -euo pipefail

here="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
golden="$(CDPATH='' cd -- "$here/../../.." && pwd)"
control="$here/../s18-readme.sh"
catalog="$golden/../../catalog/kubernetes-cluster.yaml"

work="$(mktemp -d)"
trap 'rm -rf "${work:?}"' EXIT

base="$(cat "$golden/README.md")"
failed=0

# make_root NAME README: a folder with the files S18 reads, and this README.
make_root() {
  local root="$work/$1" file
  mkdir -p "$root/gcp/tasks" "$root/local/scripts/lib" "$root/local/tasks" \
    "$root/tests/tools" "$root/.github/workflows"
  for file in platform.yaml Taskfile.yml gcp/tasks/gcp.yml local/scripts/lib/preflight-checks.sh \
    local/tasks/local.yml tests/tools/install.sh; do
    cp "$golden/$file" "$root/$file"
  done
  cp "$golden"/.github/workflows/*.yml "$root/.github/workflows/"
  printf '%s\n' "$2" >"$root/README.md"
}

# expect_fail NAME README MESSAGE: S18 fails on this README, and says MESSAGE.
expect_fail() {
  local out status=0
  make_root "$1" "$2"
  out="$(bash "$control" "$work/$1" "$catalog" 2>&1)" || status=$?
  if [ "$status" -eq 0 ]; then
    printf 'case %s: S18 passed a README that it must refuse.\n' "$1"
    failed=$((failed + 1))
  elif ! grep -q -F -- "$3" <<<"$out"; then
    printf 'case %s: S18 failed, but not with "%s". It said:\n%s\n' "$1" "$3" "$out"
    failed=$((failed + 1))
  fi
}

# The README as it is: it must pass.
make_root unchanged "$base"
status=0
out="$(bash "$control" "$work/unchanged" "$catalog" 2>&1)" || status=$?
if [ "$status" -ne 0 ]; then
  printf 'case unchanged: S18 refuses the README of the golden repo:\n%s\n' "$out"
  failed=$((failed + 1))
fi

expect_fail kind-version "${base//0.33.0/0.32.0}" "KIND_VERSION"
expect_fail lite-memory "${base//2048/1024}" "LITE_MIN_MIB"
expect_fail standard-memory "${base//2560/3072}" "STANDARD_MIN_MIB"
expect_fail engine-not-first "Docker Desktop est cité ici avant le reste.

$base" "before the free engine"
expect_fail task-missing "${base//task mirror:purge/task mirror-purge}" 'task mirror:purge'
expect_fail workflow-missing "${base//release-please.yml/autre.yml}" "release-please.yml"
expect_fail refused-variable "${base//KIND_EXPERIMENTAL_PROVIDER/AUTRE_VARIABLE}" "KIND_EXPERIMENTAL_PROVIDER"
expect_fail clear-text "${base//en clair/en secret}" "en clair"
expect_fail node-restart "${base//ne promet/promet}" "restart of the node"
expect_fail em-dash "$base

Une phrase avec un tiret $(printf '\342\200\224') cadratin." "em dash"
expect_fail mark-without-step "$base

À venir : quelque chose, un jour." "À venir"
expect_fail apply-offered "$base

\`\`\`text
tofu apply
\`\`\`" "OpenTofu apply or destroy"

# The sums of kind are compared with the catalog only where the catalog is.
if [ -f "$catalog" ]; then
  sum="$(awk '/- platform: linux-amd64$/ { wanted = 1; next } wanted && /sha256:/ { gsub(/"/, "", $2); print $2; exit }' "$catalog")"
  if [ -n "$sum" ]; then
    zeros="0000000000000000000000000000000000000000000000000000000000000000"
    expect_fail kind-sum "${base//$sum/$zeros}" "differs from the catalog"
  fi
fi

if [ "$failed" -gt 0 ]; then
  exit 1
fi
