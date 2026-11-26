#!/usr/bin/env bash
# Test cases of S18 (tests/static/s18-readme.sh), run by it when it has no
# argument. Each case copies the README of the golden repo, with the files
# that S18 reads it against, into a folder of its own, breaks one thing, and
# expects S18 to fail with the message that names it. The unchanged README
# comes first and must pass: a case that fails for another reason proves
# nothing.
#
# The README is edited with awk, not with the substitution of bash: on a
# file of this size, in a UTF-8 locale, "${text//from/to}" takes minutes.
set -euo pipefail

here="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
golden="$(CDPATH='' cd -- "$here/../../.." && pwd)"
control="$here/../s18-readme.sh"
catalog="$golden/../../catalog/kubernetes-cluster.yaml"

work="$(mktemp -d)"
trap 'rm -rf "${work:?}"' EXIT

failed=0

# replace FROM TO: the README with every FROM changed into TO, on stdout.
replace() {
  awk -v from="$1" -v to="$2" '
    {
      line = $0
      out = ""
      while ((at = index(line, from)) > 0) {
        out = out substr(line, 1, at - 1) to
        line = substr(line, at + length(from))
      }
      print out line
    }' "$golden/README.md"
}

# make_root NAME README_FILE: a folder with the files S18 reads, and this README.
make_root() {
  local root="$work/$1" file
  mkdir -p "$root/gcp/tasks" "$root/local/scripts/lib" "$root/local/tasks" \
    "$root/tests/tools" "$root/.github/workflows"
  for file in platform.yaml Taskfile.yml gcp/tasks/gcp.yml local/scripts/lib/preflight-checks.sh \
    local/tasks/local.yml tests/tools/install.sh; do
    cp "$golden/$file" "$root/$file"
  done
  cp "$golden"/.github/workflows/*.yml "$root/.github/workflows/"
  cp "$2" "$root/README.md"
}

# expect_fail NAME README_FILE MESSAGE: S18 fails on this README, and says MESSAGE.
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
make_root unchanged "$golden/README.md"
status=0
out="$(bash "$control" "$work/unchanged" "$catalog" 2>&1)" || status=$?
if [ "$status" -ne 0 ]; then
  printf 'case unchanged: S18 refuses the README of the golden repo:\n%s\n' "$out"
  failed=$((failed + 1))
fi

case_file="$work/case.md"

replace 0.33.0 0.32.0 >"$case_file"
expect_fail kind-version "$case_file" "KIND_VERSION"
replace 2048 1024 >"$case_file"
expect_fail lite-memory "$case_file" "LITE_MIN_MIB"
replace 2560 3072 >"$case_file"
expect_fail standard-memory "$case_file" "STANDARD_MIN_MIB"
{
  printf 'Docker Desktop est cité ici avant le reste.\n\n'
  cat "$golden/README.md"
} >"$case_file"
expect_fail engine-not-first "$case_file" "before the free engine"
replace 'task mirror:purge' 'task mirror-purge' >"$case_file"
expect_fail task-missing "$case_file" 'task mirror:purge'
replace release-please.yml autre.yml >"$case_file"
expect_fail workflow-missing "$case_file" "release-please.yml"
replace KIND_EXPERIMENTAL_PROVIDER AUTRE_VARIABLE >"$case_file"
expect_fail refused-variable "$case_file" "KIND_EXPERIMENTAL_PROVIDER"
replace 'en clair' 'en secret' >"$case_file"
expect_fail clear-text "$case_file" "en clair"
replace 'ne promet' 'promet' >"$case_file"
expect_fail node-restart "$case_file" "restart of the node"
{
  cat "$golden/README.md"
  printf '\nUne phrase avec un tiret %s cadratin.\n' "$(printf '\342\200\224')"
} >"$case_file"
expect_fail em-dash "$case_file" "em dash"
{
  cat "$golden/README.md"
  printf '\nÀ venir : quelque chose, un jour.\n'
} >"$case_file"
expect_fail mark-without-step "$case_file" "À venir"
{
  cat "$golden/README.md"
  # shellcheck disable=SC2016 # backticks of a Markdown fence, not a command
  printf '\n```text\ntofu apply\n```\n'
} >"$case_file"
expect_fail apply-offered "$case_file" "OpenTofu apply or destroy"

# The sums of kind are compared with the catalog only where the catalog is.
if [ -f "$catalog" ]; then
  sum="$(awk '/- platform: linux-amd64$/ { wanted = 1; next } wanted && /sha256:/ { gsub(/"/, "", $2); print $2; exit }' "$catalog")"
  if [ -n "$sum" ]; then
    replace "$sum" 0000000000000000000000000000000000000000000000000000000000000000 >"$case_file"
    expect_fail kind-sum "$case_file" "differs from the catalog"
  fi
fi

if [ "$failed" -gt 0 ]; then
  exit 1
fi
