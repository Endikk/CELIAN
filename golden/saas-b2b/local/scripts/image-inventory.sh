#!/usr/bin/env bash
# Inventory of the images of a profile of the local layer (spec 001, FR-021;
# research RS-24), computed from the files of the repository at each run,
# never copied by hand:
# - the node image of local/kind/cluster.yaml;
# - the mirror image, MIRROR_IMAGE of local/tasks/local.yml;
# - the image fields of local/vendor/, local/platform/ and local/data/;
# - the image fields of the render of local/k8s/<profile>, once it exists
#   (step 8), rendered by the Kustomize of kubectl, which reads no kubeconfig
#   (research RS-24);
# - local/security/unlisted-images, the images that no file names.
#
# Prints one reference per line, written in full as Docker reads it
# (docker.io/library/postgres:18...), sorted, without repeats. Each carries
# a digest, or sits under saas-b2b.invalid, built by task up. A reference
# without digest stops the inventory, naming its file, except the vendored
# ones of the closed list below, which never run. Checked by S25
# (local/tests/static/s25-inventory.sh); read by tests/scan/scan-images.sh.
#
# Usage: local/scripts/image-inventory.sh lite
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
CDPATH='' cd -- "$root"

kind_config="local/kind/cluster.yaml"
local_tasks="local/tasks/local.yml"
unlisted="local/security/unlisted-images"

# Vendored images named by tag that never run, one repository per line. Each
# addition is reviewed by [SECU].
# - docker.io/envoyproxy/ratelimit: named by the configuration of the Envoy
#   Gateway controller under rateLimitDeployment, run only once rateLimit is
#   set, which S22 refuses without a digest (ADR-005, condition 1; research
#   RS-02). Pinned by digest one day, it joins the inventory by itself.
not_run_repositories="docker.io/envoyproxy/ratelimit"

die() {
  printf 'image-inventory.sh: %s\n' "$1" >&2
  exit 1
}

profile="${1:-}"
case "$profile" in
  lite) ;;
  standard) die "the standard profile arrives with step 12 of spec 001: its inventory is not delivered yet." ;;
  *) die "usage: local/scripts/image-inventory.sh lite" ;;
esac

# Writes reference $1 in full, as distribution/reference v0.6.0 reads it
# (research RS-24): docker.io when the first element has no ".", no ":" and
# no upper case and is not localhost; library/ before a single name on
# docker.io; index.docker.io read as docker.io.
full_reference() {
  local ref="$1" first rest
  case "$ref" in
    */*) ;;
    *)
      printf 'docker.io/library/%s\n' "$ref"
      return 0
      ;;
  esac
  first="${ref%%/*}"
  rest="${ref#*/}"
  case "$first" in
    localhost | *.* | *:* | *[A-Z]*)
      if [ "$first" = "index.docker.io" ]; then
        first="docker.io"
      fi
      ;;
    *)
      rest="$ref"
      first="docker.io"
      ;;
  esac
  if [ "$first" = "docker.io" ]; then
    case "$rest" in
      */*) ;;
      *) rest="library/$rest" ;;
    esac
  fi
  printf '%s/%s\n' "$first" "$rest"
}

# The repository of a full reference: no digest, no tag after the last "/".
repository_of() {
  local name="${1%%@*}" last
  last="${name##*/}"
  printf '%s/%s\n' "${name%/*}" "${last%%:*}"
}

# "<source>:<line>|<value>" for each image field of YAML file $1; $2, when
# given, names the source in messages instead of the file.
image_fields() {
  awk -v source="${2:-$1}" '
    {
      line = $0
      sub(/^[ \t]*(-[ \t]+)?/, "", line)
      if (line !~ /^image:[ \t]/) next
      sub(/^image:[ \t]+/, "", line)
      sub(/[ \t]+#.*$/, "", line)
      gsub(/["\047]/, "", line)
      sub(/[ \t]+$/, "", line)
      if (line != "") print source ":" FNR "|" line
    }
  ' "$1"
}

work="$(mktemp -d)"
trap 'rm -rf "${work:?}"' EXIT
found="$work/found"
: >"$found"

[ -f "$kind_config" ] || die "$kind_config is missing: it names the node image (spec 001, T046)."
image_fields "$kind_config" >>"$found"
if ! grep -q "^$kind_config:" "$found"; then
  die "$kind_config names no node image: the node is the first image of the inventory (FR-021)."
fi

[ -f "$local_tasks" ] || die "$local_tasks is missing: it names the mirror image (spec 001, T050)."
awk -v source="$local_tasks" '
  /^[ \t]*MIRROR_IMAGE:[ \t]*[^ \t]/ { v = $2; gsub(/["\047]/, "", v); print source ":" FNR "|" v }
' "$local_tasks" >>"$found"
if ! grep -q "^$local_tasks:" "$found"; then
  die "$local_tasks has no MIRROR_IMAGE: the mirror runs on the engine of the machine and belongs to the inventory (ADR-011, condition 8)."
fi

while IFS= read -r file; do
  image_fields "$file" >>"$found"
done < <(find local/vendor local/platform local/data -type f \( -name '*.yaml' -o -name '*.yml' \) 2>/dev/null | LC_ALL=C sort)

if [ -f "local/k8s/$profile/kustomization.yaml" ]; then
  if ! command -v kubectl >/dev/null 2>&1; then
    die "kubectl is not on PATH: it renders local/k8s/$profile, whose images belong to the inventory."
  fi
  if ! kubectl kustomize "local/k8s/$profile" >"$work/render.yaml" 2>"$work/render.err"; then
    die "kubectl kustomize local/k8s/$profile fails: $(cat "$work/render.err")"
  fi
  image_fields "$work/render.yaml" "render of local/k8s/$profile" >>"$found"
fi

[ -f "$unlisted" ] || die "$unlisted is missing: it lists the images that no file names (research RS-24)."
grep -n -v -E '^[[:space:]]*(#|$)' "$unlisted" |
  sed -e 's/^\([0-9]*\):[[:space:]]*/\1|/' -e 's/[[:space:]]*$//' -e "s#^#$unlisted:#" >>"$found" || true

: >"$work/refs"
: >"$work/problems"
while IFS='|' read -r where ref; do
  full="$(full_reference "$ref")"
  case "$full" in
    saas-b2b.invalid/*)
      printf '%s\n' "$full" >>"$work/refs"
      continue
      ;;
  esac
  if printf '%s\n' "$full" | grep -q -E '@sha256:[0-9a-f]{64}$'; then
    printf '%s\n' "$full" >>"$work/refs"
    continue
  fi
  case "$where" in
    local/vendor/*)
      # shellcheck disable=SC2086 # one repository per word, none with a blank
      if printf '%s\n' $not_run_repositories | grep -F -x -q -e "$(repository_of "$full")"; then
        continue
      fi
      ;;
  esac
  printf '%s: %s has no digest (@sha256:<64 hex digits>); only images under saas-b2b.invalid, built by task up, go without one (S25, FR-021).\n' \
    "$where" "$full" >>"$work/problems"
done <"$found"

if [ -s "$work/problems" ]; then
  cat "$work/problems" >&2
  exit 1
fi
LC_ALL=C sort -u "$work/refs"
