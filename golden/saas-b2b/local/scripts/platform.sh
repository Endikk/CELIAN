#!/usr/bin/env bash
# The platform of the local cluster: Gateway API, Envoy Gateway, and the
# EnvoyProxy and GatewayClass of the local layer (spec 001, plan, "Ce que
# fait task up", point 4; ADR-005; contracts/task-cli.md).
#
# Usage: bash local/scripts/platform.sh check IMAGE | up IMAGE
#   check  checks local/vendor/: ordinary files at (gateway-api|envoy-gateway)/<name>.yaml
#          under MAX_VENDOR_FILE_BYTES, each against local/vendor/SHA256SUMS
#          (every file listed, every listed file there, every sum equal),
#          then that the vendored render runs IMAGE. It calls no kubectl and
#          creates nothing: task up runs it before it creates the cluster
#   up     runs check again, then applies, from the files of the repository
#          only (ADR-004, condition 4): the CRDs of Gateway API, the CRDs of
#          Envoy Gateway, the namespace of Envoy Gateway, its controller,
#          then the EnvoyProxy and the GatewayClass; it waits until the
#          controller is available and the GatewayClass accepted. The
#          controller watches its namespace and the one of the application
#          alone (ADR-005, complement of 2026-11-25): up stops before the
#          controller when the namespace of the application is missing,
#          since task up creates it with the Secrets
#   IMAGE  the controller image, by tag and digest: ENVOY_GATEWAY_IMAGE of
#          local/tasks/local.yml
#
# Every kubectl call goes through kube of lib/local-env.sh, which names the
# kubeconfig of the project and its context (S19). Everything is applied
# server-side, as BENCH-004 applied the CRDs of Envoy Gateway
# (tests/bench/bench-004-gateway.sh, line 629). The vendored render keeps
# the objects that Helm runs as hooks (certgen and its rights); they are
# applied with the rest, in the order of the file, and certgen leaves
# existing certificates as they are (research RS-02). Nothing here creates
# or removes a container, a network or a volume.
set -euo pipefail

here="${BASH_SOURCE[0]}"
case "$here" in
  */*) here="${here%/*}" ;;
  *) here="." ;;
esac
# shellcheck disable=SC1091 # lib/local-env.sh is checked on its own
. "$here/lib/local-env.sh"
# shellcheck disable=SC1091 # lib/pull-wait.sh is checked on its own
. "$here/lib/pull-wait.sh"
root="$(CDPATH='' cd -- "$here/../.." && pwd)"

readonly VENDOR="$root/local/vendor"
readonly SUMS="$VENDOR/SHA256SUMS"
readonly GATEWAY_API_CRDS="$VENDOR/gateway-api/standard-install.yaml"
readonly ENVOY_GATEWAY_CRDS="$VENDOR/envoy-gateway/gateway-crds-helm.yaml"
readonly ENVOY_GATEWAY_RENDER="$VENDOR/envoy-gateway/gateway-helm.yaml"
readonly PLATFORM="$root/local/platform"
readonly CONTROLLER_NAMESPACE="envoy-gateway-system"
readonly CONTROLLER_DEPLOYMENT="envoy-gateway"
readonly GATEWAY_CLASS="saas-b2b"
readonly CONTROLLER_REPOSITORY="docker.io/envoyproxy/gateway"
# How long the CRDs get to be established, the controller to be available
# and the GatewayClass to be accepted. The controller waits for its image,
# pulled through the mirror, then for the certificates of certgen; the
# platform answered in 75.9 s with the gateway images missing from the node
# in BENCH-004 (ADR-005).
readonly CRD_WAIT="60s"
readonly CONTROLLER_WAIT_SECONDS=300
readonly CLASS_WAIT="60s"
# The size cap of a vendored file, in bytes: a little above the largest render
# of today, gateway-crds-helm.yaml (2.86 MB). A bigger file is refused, so
# that a vendored file cannot swell unseen (S02).
readonly MAX_VENDOR_FILE_BYTES=3145728

die() {
  printf 'platform: %s\n' "$1" >&2
  exit 1
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

# verify_sums: local/vendor/ holds ordinary files only, each at a path of the
# form (gateway-api|envoy-gateway)/<name>.yaml and under the size cap; every
# one of them but SHA256SUMS has one line in it, and every line names a file
# whose SHA-256 it gives (S02). A symbolic link, a special file, another
# folder or another extension is refused even when its sum is listed.
verify_sums() {
  local line number=0 sum file listed=$'\n' found size
  [ -f "$SUMS" ] || die "local/vendor/SHA256SUMS is missing: the vendored manifests cannot be checked. Restore it from the repository. Nothing was applied."
  [ ! -L "$SUMS" ] || die "local/vendor/SHA256SUMS is a symbolic link. Restore it from the repository. Nothing was applied."
  while IFS= read -r line || [ -n "$line" ]; do
    number=$((number + 1))
    if ! [[ $line =~ ^([0-9a-f]{64})\ \ ((gateway-api|envoy-gateway)/[A-Za-z0-9._-]+\.yaml)$ ]]; then
      die "local/vendor/SHA256SUMS, line $number (\"${line//[![:print:]]/?}\"), is not \"<sha256>  (gateway-api|envoy-gateway)/<name>.yaml\". Restore it from the repository. Nothing was applied."
    fi
    sum="${BASH_REMATCH[1]}"
    file="${BASH_REMATCH[2]}"
    [ -f "$VENDOR/$file" ] || die "local/vendor/$file is listed in SHA256SUMS but missing. Restore it from the repository. Nothing was applied."
    [ ! -L "$VENDOR/$file" ] || die "local/vendor/$file is a symbolic link: ordinary files only. Restore it from the repository. Nothing was applied."
    size="$(wc -c <"$VENDOR/$file" | tr -d ' ')"
    [ "$size" -le "$MAX_VENDOR_FILE_BYTES" ] || die "local/vendor/$file is $size bytes, above the cap of $MAX_VENDOR_FILE_BYTES. Restore it from the repository. Nothing was applied."
    if [ "$(sha256_of "$VENDOR/$file")" != "$sum" ]; then
      die "local/vendor/$file differs from its SHA-256 in SHA256SUMS: it was changed. Restore it from the repository. Nothing was applied."
    fi
    listed="$listed$file"$'\n'
  done <"$SUMS"
  while IFS= read -r found; do
    found="${found#"$VENDOR"/}"
    [ "$found" = SHA256SUMS ] && continue
    case "$listed" in
      *$'\n'"$found"$'\n'*) ;;
      *) die "local/vendor/$found has no SHA-256 in SHA256SUMS, or is not of the form (gateway-api|envoy-gateway)/<name>.yaml: nothing unchecked is applied. Remove it, or add its sum. Nothing was applied." ;;
    esac
  done < <(find "$VENDOR" ! -type d)
}

# verify_render IMAGE: the render of the controller names the controller
# repository with IMAGE only, so that a reference moved in local.yml without
# a new render stops here (S22 reads the render in full).
verify_render() {
  local image="$1" line value seen=no
  if ! [[ $image =~ ^${CONTROLLER_REPOSITORY//./\\.}:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[a-f0-9]{64}$ ]]; then
    die "\"${image//[![:print:]]/?}\" is not an image of $CONTROLLER_REPOSITORY by tag and digest: run task up, which passes ENVOY_GATEWAY_IMAGE of local/tasks/local.yml. Nothing was applied."
  fi
  while IFS= read -r line; do
    value="${line#*image: }"
    case "$value" in
      "$CONTROLLER_REPOSITORY":* | "$CONTROLLER_REPOSITORY"@*) ;;
      *) continue ;;
    esac
    [ "$value" = "$image" ] || die "the vendored render of Envoy Gateway runs $value, and local/tasks/local.yml gives $image: redo the render of the same release (research RS-02), or set ENVOY_GATEWAY_IMAGE back. Nothing was applied."
    seen=yes
  done < <(grep 'image: ' "$ENVOY_GATEWAY_RENDER")
  [ "$seen" = yes ] || die "the vendored render of Envoy Gateway runs no image of $CONTROLLER_REPOSITORY. Restore it from the repository. Nothing was applied."
}

check() {
  local file
  verify_sums
  for file in "$GATEWAY_API_CRDS" "$ENVOY_GATEWAY_CRDS" "$ENVOY_GATEWAY_RENDER"; do
    [ -f "$file" ] || die "${file#"$root"/} is missing. Restore it from the repository. Nothing was applied."
  done
  for file in namespace.yaml envoy-proxy.yaml gateway-class.yaml; do
    [ -f "$PLATFORM/$file" ] || die "local/platform/$file is missing. Restore it from the repository. Nothing was applied."
  done
  verify_render "$1"
}

# watched_namespaces_exist: every namespace of an object of the controller
# render, but its own, exists. The controller watches the namespace of the
# application alone with its own (ADR-005, complement of 2026-11-25), and
# the render holds its Role and RoleBinding there: kubectl would refuse
# them in a namespace that does not exist. task up creates it with the
# Secrets, before the platform.
watched_namespaces_exist() {
  local namespace found
  while IFS= read -r namespace; do
    [ "$namespace" = "$CONTROLLER_NAMESPACE" ] && continue
    found="$(kube get namespace "$namespace" --ignore-not-found --output name)" ||
      die "cannot read the namespace $namespace; the messages of kubectl are above. The controller was not applied."
    [ -n "$found" ] ||
      die "the namespace $namespace, which the controller of Envoy Gateway watches, does not exist: task up creates it with the Secrets, before the platform. The controller was not applied."
  done < <(sed -n -E 's/^  namespace: "?([a-z0-9-]+)"?$/\1/p' "$ENVOY_GATEWAY_RENDER" | LC_ALL=C sort -u)
}

# apply FILE...: server-side apply of files of the repository.
apply() {
  local args=() file
  for file in "$@"; do
    args+=(-f "$file")
  done
  kube apply --server-side "${args[@]}" >/dev/null
}

up() {
  local image="$1"
  check "$image"
  apply "$GATEWAY_API_CRDS" || die "the CRDs of Gateway API were not applied; the messages of kubectl are above."
  apply "$ENVOY_GATEWAY_CRDS" || die "the CRDs of Envoy Gateway were not applied; the messages of kubectl are above."
  kube wait --for=condition=Established --timeout="$CRD_WAIT" crd --all >/dev/null ||
    die "the CRDs are not established within $CRD_WAIT. Run task down, then task up."
  printf 'Platform: CRDs of Gateway API and of Envoy Gateway established, from local/vendor/.\n'
  watched_namespaces_exist
  apply "$PLATFORM/namespace.yaml" "$ENVOY_GATEWAY_RENDER" ||
    die "the controller of Envoy Gateway was not applied; the messages of kubectl are above."
  # A pull that fails stops the wait at once, naming the registry (T127).
  if ! wait_rollout "$CONTROLLER_NAMESPACE" "deployment/$CONTROLLER_DEPLOYMENT" "$CONTROLLER_WAIT_SECONDS"; then
    die "the controller of Envoy Gateway is not available within $CONTROLLER_WAIT_SECONDS s. Look at its pods: kubectl --kubeconfig $KUBECONFIG_FILE --context $KUBE_CONTEXT --namespace $CONTROLLER_NAMESPACE get pods."
  fi
  apply "$PLATFORM/envoy-proxy.yaml" "$PLATFORM/gateway-class.yaml" ||
    die "the EnvoyProxy and the GatewayClass were not applied; the messages of kubectl are above."
  kube wait --for=condition=Accepted --timeout="$CLASS_WAIT" "gatewayclass/$GATEWAY_CLASS" >/dev/null ||
    die "the GatewayClass $GATEWAY_CLASS is not accepted within $CLASS_WAIT: its EnvoyProxy may be refused. Look at its status: kubectl --kubeconfig $KUBECONFIG_FILE --context $KUBE_CONTEXT get gatewayclass $GATEWAY_CLASS --output yaml."
  printf 'Platform: Envoy Gateway %s available; GatewayClass %s accepted.\n' "${image%@*}" "$GATEWAY_CLASS"
}

case "${1:-}" in
  check) check "${2:-}" ;;
  up) up "${2:-}" ;;
  *) die "usage: bash local/scripts/platform.sh check IMAGE | up IMAGE" ;;
esac
