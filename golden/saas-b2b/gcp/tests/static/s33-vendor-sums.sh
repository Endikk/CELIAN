#!/usr/bin/env bash
# control: S33
# carries: FR-012; ADR-010, conditions 5 and 6; ADR-004, condition 4; research RS-16
#
# The manifest of Config Sync that E16 applies on kind is third-party text, kept
# byte for byte in gcp/vendor/ with its SHA-256 in gcp/vendor/SHA256SUMS, as
# the platform of the local layer is (S02). Each file but SHA256SUMS and the
# list of images has a line there, each line names a file that exists, each sum
# matches, and no file is a link. gcp/vendor/config-sync/images names, with a
# digest, exactly the images that the manifest writes by tag: an image added by
# a new version and not listed fails here, before E16 runs it by tag (ADR-010,
# condition 6).
set -uo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
CDPATH='' cd -- "$root" || exit 2

vendor="gcp/vendor"
sums_file="$vendor/SHA256SUMS"
manifest="$vendor/config-sync/config-sync-manifest.yaml"
images_file="$vendor/config-sync/images"
failures=0

fail() {
  failures=$((failures + 1))
  printf '%s\n' "$1" >&2
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

for file in "$sums_file" "$manifest" "$images_file"; do
  if [ ! -f "$file" ]; then
    echo "$file is missing: the manifest of Config Sync for E16 is not vendored (spec 001, T132)." >&2
    exit 1
  fi
done

listed="$(awk '{ print $2 }' "$sums_file" | LC_ALL=C sort)"
present="$(CDPATH='' cd -- "$vendor" && find . -type f ! -name SHA256SUMS ! -name images | sed 's|^\./||' | LC_ALL=C sort)"
if [ "$listed" != "$present" ]; then
  fail "$sums_file and the files of $vendor differ: listed [$(printf '%s' "$listed" | tr '\n' ' ')], present [$(printf '%s' "$present" | tr '\n' ' ')]."
fi
if [ -n "$(find "$vendor" -type l)" ]; then
  fail "$vendor holds a symbolic link: only ordinary files, whose bytes the sums cover."
fi
while read -r sum file; do
  [ -f "$vendor/$file" ] || continue
  if [ "$(sha256_of "$vendor/$file")" != "$sum" ]; then
    fail "$vendor/$file does not match its SHA-256 in $sums_file: the file is third-party bytes, vendored again from the release, never edited."
  fi
done <"$sums_file"

# The images of the manifest, as it writes them, and the list that pins them.
in_manifest="$(awk '$1 == "image:" && NF == 2 { print $2 }' "$manifest" | LC_ALL=C sort -u)"
in_list="$(awk '$1 !~ /^#/ && NF == 2 { print $1 }' "$images_file" | LC_ALL=C sort -u)"
if [ -z "$in_manifest" ]; then
  fail "$manifest names no image: the check reads the lines 'image: <reference>'."
fi
if [ "$in_manifest" != "$in_list" ]; then
  fail "The images of $manifest and of $images_file differ: manifest [$(printf '%s' "$in_manifest" | tr '\n' ' ')], list [$(printf '%s' "$in_list" | tr '\n' ' ')]."
fi
while read -r ref digest; do
  case "$ref" in '#'* | '') continue ;; esac
  if ! printf '%s' "$digest" | grep -q -E '^sha256:[0-9a-f]{64}$'; then
    fail "$images_file: $ref has the digest '$digest', sha256: and 64 hexadecimal digits expected."
  fi
  case "$ref" in
    *@*) fail "$images_file: $ref already holds a digest: the manifest writes tags, the digest is the second column." ;;
  esac
done <"$images_file"

if [ "$failures" -gt 0 ]; then
  exit 1
fi
echo "The manifest of Config Sync is vendored with its sum, and its $(printf '%s\n' "$in_manifest" | wc -l | tr -d ' ') images are pinned by digest."
