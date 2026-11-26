#!/usr/bin/env bash
# control: S25
# carries: FR-021; research RS-24; ADR-011, condition 8
#
# The inventory of the images of a profile is computed from the files of the
# repository, never copied by hand (research RS-24): the node image of the
# kind configuration, the image of the mirror task, the images of the
# vendored files, of local/platform/ and local/data/, the render of
# local/k8s/<profile> once it exists, and local/security/unlisted-images,
# the images that no file names, each with a digest. Checks:
# - every entry of local/security/unlisted-images carries a digest;
# - on the repository, local/scripts/image-inventory.sh lite lists each of
#   these images, written in full, each with a digest or under
#   saas-b2b.invalid;
# - on a small fixture tree, the exact list it must print, then the cases it
#   must refuse: an image without digest, a missing node or mirror image, a
#   profile not delivered.
# kubectl renders the fixture with its Kustomize, which reads no kubeconfig
# (research RS-24).
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
CDPATH='' cd -- "$root"

script="local/scripts/image-inventory.sh"
unlisted="local/security/unlisted-images"
problems=0

report() {
  problems=$((problems + 1))
  printf '%s\n' "$1"
}

for file in "$script" "$unlisted"; do
  if [ ! -f "$file" ]; then
    echo "$file is missing: the inventory of the images is computed there (spec 001, T115, T116)." >&2
    exit 1
  fi
done
if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is not on PATH: S25 renders a fixture with kubectl kustomize." >&2
  exit 1
fi

digest='@sha256:[0-9a-f]{64}$'

# The entries of a list file: lines that are neither blank nor comments.
entries() {
  grep -v -E '^[[:space:]]*(#|$)' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' || true
}

# 1. Each entry of the unlisted images carries a digest.
while IFS= read -r ref; do
  if ! printf '%s\n' "$ref" | grep -q -E "$digest"; then
    report "$unlisted: $ref has no digest (@sha256:<64 hex digits>)."
  fi
done < <(entries "$unlisted")

# 1b. The proxy of Envoy Gateway is named by the EnvoyProxy of
# local/platform/ (ADR-005, complement of 2026-11-26): the inventory reads it
# there and Renovate follows it there. The list of unlisted images does not
# repeat it: a second copy would outlive the first at the next update, and
# the scan would take the old image for a live one.
proxy_pin='^[[:space:]]*image:[[:space:]]*docker\.io/envoyproxy/envoy:[A-Za-z0-9._-]+@sha256:[0-9a-f]{64}$'
if ! grep -q -E "$proxy_pin" local/platform/envoy-proxy.yaml; then
  report "local/platform/envoy-proxy.yaml pins no proxy image, docker.io/envoyproxy/envoy by tag and digest (ADR-005, complement of 2026-11-26)."
fi
if entries "$unlisted" | grep -q 'envoyproxy/envoy'; then
  report "$unlisted names the proxy of Envoy Gateway, which local/platform/envoy-proxy.yaml names: remove the line."
fi

# 2. The inventory of the repository.
if ! out="$(bash "$script" lite 2>&1)"; then
  report "$script lite fails:"
  printf '%s\n' "$out"
  out=""
fi
if [ -z "$out" ] && [ "$problems" -eq 0 ]; then
  report "$script lite prints nothing."
fi
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  case "$ref" in
    saas-b2b.invalid/*) continue ;;
  esac
  if ! printf '%s\n' "$ref" | grep -q -E "$digest"; then
    report "$script lite lists $ref, without digest and outside saas-b2b.invalid."
  fi
done < <(printf '%s\n' "$out")

# True when the inventory lists $1, written in full by the script.
listed_in_output() {
  printf '%s\n' "$out" | grep -F -x -q -e "$1" -e "docker.io/$1" -e "docker.io/library/$1"
}

# The images that the inventory must hold: "<file>|<reference>".
expected_refs() {
  local file
  awk '/^[[:space:]]*-?[[:space:]]*image:[[:space:]]*[^[:space:]]/ { v = $0; sub(/^[^:]*:[[:space:]]*/, "", v); sub(/[[:space:]]+#.*$/, "", v); gsub(/["'\'']/, "", v); print FILENAME "|" v }' \
    local/kind/cluster.yaml
  awk '/^[[:space:]]*(MIRROR_IMAGE|ENVOY_GATEWAY_IMAGE):/ { v = $2; gsub(/["'\'']/, "", v); print FILENAME "|" v }' local/tasks/local.yml
  entries "$unlisted" | sed -e "s#^#$unlisted|#"
  while IFS= read -r file; do
    awk '/^[[:space:]]*-?[[:space:]]*image:[[:space:]]*[^[:space:]]*@sha256:/ { v = $0; sub(/^[^:]*:[[:space:]]*/, "", v); sub(/[[:space:]]+#.*$/, "", v); gsub(/["'\'']/, "", v); print FILENAME "|" v }' "$file"
  done < <(find local/vendor local/platform local/data -type f \( -name '*.yaml' -o -name '*.yml' \) 2>/dev/null | LC_ALL=C sort)
}

while IFS='|' read -r file ref; do
  [ -n "$ref" ] || continue
  if ! listed_in_output "$ref"; then
    report "$script lite does not list $ref, named by $file."
  fi
done < <(expected_refs)

# 3. A fixture tree, with the exact list it must print.
work="$(mktemp -d)"
trap 'rm -rf "${work:?}"' EXIT

hex() {
  printf '%064d' 0 | tr 0 "$1"
}
node="kindest/node:v0@sha256:$(hex a)"
proxy="docker.io/envoyproxy/envoy:distroless-v0@sha256:$(hex b)"
controller="docker.io/envoyproxy/gateway:v0@sha256:$(hex c)"
postgres="postgres:18@sha256:$(hex d)"
rendered="docker.io/example/rendered:1@sha256:$(hex e)"
mirror="ghcr.io/project-zot/zot:v0@sha256:$(hex f)"

# make_fixture DIR: a tree with one image from each source.
make_fixture() {
  local dir="$1"
  mkdir -p "$dir/local/scripts" "$dir/local/kind" "$dir/local/tasks" "$dir/local/security" \
    "$dir/local/vendor/envoy-gateway" "$dir/local/data" "$dir/local/k8s/lite"
  cp "$script" "$dir/local/scripts/image-inventory.sh"
  printf '%s\n' 'kind: Cluster' 'nodes:' '  - role: control-plane' "    image: $node" >"$dir/local/kind/cluster.yaml"
  printf '%s\n' 'vars:' '  # renovate: datasource=docker' "  MIRROR_IMAGE: $mirror" >"$dir/local/tasks/local.yml"
  printf '%s\n' '# The proxy of Envoy Gateway, named by no file.' "$proxy" >"$dir/local/security/unlisted-images"
  printf '%s\n' 'data:' '  envoy-gateway.yaml: |' '    rateLimitDeployment:' '      container:' \
    '        image: docker.io/envoyproxy/ratelimit:5ae0682e' '---' 'spec:' '  containers:' \
    "    - image: $controller" >"$dir/local/vendor/envoy-gateway/gateway-helm.yaml"
  printf '%s\n' 'spec:' '  containers:' '    - name: postgres' "      image: \"$postgres\"" >"$dir/local/data/postgres.yaml"
  printf '%s\n' 'apiVersion: kustomize.config.k8s.io/v1beta1' 'kind: Kustomization' 'resources:' '  - pod.yaml' \
    >"$dir/local/k8s/lite/kustomization.yaml"
  printf '%s\n' 'apiVersion: v1' 'kind: Pod' 'metadata:' '  name: example' 'spec:' '  containers:' \
    '    - name: rendered' "      image: $rendered" '    - name: built' '      image: saas-b2b.invalid/api:local' \
    >"$dir/local/k8s/lite/pod.yaml"
}

expected="$(printf '%s\n' \
  "$proxy" \
  "$controller" \
  "$rendered" \
  "docker.io/$node" \
  "docker.io/library/$postgres" \
  "$mirror" \
  "saas-b2b.invalid/api:local" | LC_ALL=C sort)"

make_fixture "$work/base"
if ! got="$(bash "$work/base/local/scripts/image-inventory.sh" lite 2>&1)"; then
  report "$script fails on the fixture tree:"
  printf '%s\n' "$got"
elif [ "$got" != "$expected" ]; then
  report "$script prints on the fixture tree:"
  printf '%s\n' "$got" "instead of:" "$expected"
fi

# refused NAME FRAGMENT PROFILE: the fixture $work/NAME must be refused by
# a message that holds FRAGMENT.
refused() {
  local name="$1" fragment="$2" profile="$3" got
  if got="$(bash "$work/$name/local/scripts/image-inventory.sh" "$profile" 2>&1)"; then
    report "fixture $name: the inventory passes, yet it must be refused with: $fragment"
  elif ! printf '%s\n' "$got" | grep -F -q -e "$fragment"; then
    report "fixture $name: refused, but no message holds: $fragment"
    printf '%s\n' "$got"
  fi
}

make_fixture "$work/unlisted-without-digest"
printf '%s\n' 'docker.io/envoyproxy/envoy:distroless-v0' >"$work/unlisted-without-digest/local/security/unlisted-images"
refused unlisted-without-digest "docker.io/envoyproxy/envoy:distroless-v0 has no digest" lite

make_fixture "$work/vendored-by-tag"
printf '%s\n' '---' 'spec:' '  containers:' '    - image: docker.io/example/other:1.0' \
  >>"$work/vendored-by-tag/local/vendor/envoy-gateway/gateway-helm.yaml"
refused vendored-by-tag "docker.io/example/other:1.0 has no digest" lite

make_fixture "$work/data-by-tag"
printf '%s\n' 'spec:' '  containers:' '    - image: postgres:18' >"$work/data-by-tag/local/data/postgres.yaml"
refused data-by-tag "docker.io/library/postgres:18 has no digest" lite

make_fixture "$work/rendered-by-tag"
printf '%s\n' 'apiVersion: v1' 'kind: Pod' 'metadata:' '  name: example' 'spec:' '  containers:' \
  '    - name: rendered' '      image: docker.io/example/rendered:1' >"$work/rendered-by-tag/local/k8s/lite/pod.yaml"
refused rendered-by-tag "docker.io/example/rendered:1 has no digest" lite

make_fixture "$work/no-node-image"
printf '%s\n' 'kind: Cluster' 'nodes:' '  - role: control-plane' >"$work/no-node-image/local/kind/cluster.yaml"
refused no-node-image "no node image" lite

make_fixture "$work/no-mirror-image"
printf '%s\n' 'vars:' '  OTHER: value' >"$work/no-mirror-image/local/tasks/local.yml"
refused no-mirror-image "no MIRROR_IMAGE" lite

make_fixture "$work/profiles"
refused profiles "step 12" standard
refused profiles "usage:" heavy

# 4. The gcp profile lists the images of the renders of gcp/k8s/<composition>/,
# as written and without a digest requirement (the images built for gcp get
# theirs when pushed). A Component is not rendered on its own, and a tree
# without gcp/k8s lists nothing. S26 reads this list to refuse a reported
# image deployed on gcp.
make_fixture "$work/gcp"
mkdir -p "$work/gcp/gcp/k8s/prod" "$work/gcp/gcp/k8s/component"
printf '%s\n' 'apiVersion: kustomize.config.k8s.io/v1beta1' 'kind: Kustomization' 'resources:' '  - pod.yaml' \
  >"$work/gcp/gcp/k8s/prod/kustomization.yaml"
printf '%s\n' 'apiVersion: v1' 'kind: Pod' 'metadata:' '  name: example' 'spec:' '  containers:' \
  '    - name: app' '      image: europe-docker.pkg.dev/project/repo/api:1' '    - name: proxy' '      image: nginx:1' \
  >"$work/gcp/gcp/k8s/prod/pod.yaml"
printf '%s\n' 'apiVersion: kustomize.config.k8s.io/v1alpha1' 'kind: Component' \
  >"$work/gcp/gcp/k8s/component/kustomization.yaml"
expected_gcp="$(printf '%s\n' 'docker.io/library/nginx:1' 'europe-docker.pkg.dev/project/repo/api:1')"
if ! got="$(bash "$work/gcp/local/scripts/image-inventory.sh" gcp 2>&1)"; then
  report "$script gcp fails on a tree with one render:"
  printf '%s\n' "$got"
elif [ "$got" != "$expected_gcp" ]; then
  report "$script gcp prints:"
  printf '%s\n' "$got" "instead of:" "$expected_gcp"
fi

make_fixture "$work/no-gcp"
if ! got="$(bash "$work/no-gcp/local/scripts/image-inventory.sh" gcp 2>&1)" || [ -n "$got" ]; then
  report "$script gcp must print nothing, and succeed, on a tree without gcp/k8s; it prints: $got"
fi

# 5. The classes of security/scan-policy.yaml against the inventory of lite:
# a reported image is in the inventory (no entry outlives its image), and no
# image built by task up is reported.
classes_helper="tests/scan/image-classes.sh"
policy_file="security/scan-policy.yaml"
if [ ! -f "$classes_helper" ]; then
  report "$classes_helper is missing: it reads the classes of $policy_file (spec 001, step 18)."
else
  if ! class_lines="$(bash "$classes_helper" "$policy_file" 2>&1)"; then
    report "$policy_file: $class_lines"
    class_lines=""
  fi
  inventory_repositories=""
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    repo="${ref%%@*}"
    last="${repo##*/}"
    inventory_repositories="$inventory_repositories
${repo%/*}/${last%%:*}"
  done < <(printf '%s\n' "$out")
  while IFS= read -r line; do
    [ "${line%%|*}" = reported ] || continue
    entry="${line#*|}"
    [ -n "$entry" ] || continue
    if ! printf '%s\n' "$inventory_repositories" | grep -F -x -q -e "$entry"; then
      report "$policy_file: reported image $entry is in no image of the inventory of lite: remove it, or the inventory lost the image."
    fi
    case "$entry" in
      saas-b2b.invalid | saas-b2b.invalid/*)
        report "$policy_file: $entry is built by the project, and a built image blocks: it is not reported."
        ;;
    esac
  done < <(printf '%s\n' "$class_lines")
fi

if [ "$problems" -gt 0 ]; then
  exit 1
fi
echo "The inventory of the lite profile is computed from the repository, each image with a digest or built by task up."
