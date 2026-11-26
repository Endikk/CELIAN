#!/usr/bin/env bash
# Tests of scripts/ci/check-envoy-gateway-render.sh (spec 001, tasks.md, gap
# 44), run with a stand-in helm (tests/ci/fakes/helm) and a copy of the files
# the script reads, so they need neither Helm nor the network. The accepted
# case pins the commands and options of research RS-02: the stand-in prints
# them, and the expected files below spell them out.
#
# Usage: bash tests/ci/check-envoy-gateway-render-test.sh
set -euo pipefail

here="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../../scripts/ci/check-envoy-gateway-render.sh"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

controller_sum="sha256:c2243d43518bed91d3ed8c2db849a4b7a14ac9b96eb019f2ab104bb1ca8572b1"
chart_sum="sha256:dcb82a14c04b426615a71d97222c7edf9f5ff58b800d241e71ac5784ae6dc7b7"
crds_sum="sha256:475c39aad3a05e3974a29fb80cfefe882b743e45e2ec0f751790ff0cb83bfa5d"
controller_ref="docker.io/envoyproxy/gateway:v1.10.0@$controller_sum"
proxy_ref="docker.io/envoyproxy/envoy:distroless-v1.40.2@sha256:09ca6f2140a61ad8df11779a4a30d52b48433d444466328494f9188c9c35eded"

failures=0

# new_golden DIR: a golden repo with the three references, the namespace of
# the application, and the two vendored renders the stand-in helm is
# expected to give: the controller chart with the watch of research RS-02
# (ADR-005, complement of 2026-11-25).
new_golden() {
  local dir="$1"
  mkdir -p "$dir/local/tasks" "$dir/local/vendor/envoy-gateway" "$dir/local/platform" "$dir/k8s/base"
  printf "spec:\n  provider:\n    kubernetes:\n      envoyDeployment:\n        container:\n          image: %s\n" "$proxy_ref" >"$dir/local/platform/envoy-proxy.yaml"
  printf 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: shop\n' >"$dir/k8s/base/namespace.yaml"
  {
    printf 'vars:\n'
    printf '  ENVOY_GATEWAY_IMAGE: %s\n' "$controller_ref"
    printf '  ENVOY_GATEWAY_HELM_IMAGE: docker.io/envoyproxy/gateway-helm:v1.10.0@%s\n' "$chart_sum"
    printf '  ENVOY_GATEWAY_CRDS_HELM_IMAGE: docker.io/envoyproxy/gateway-crds-helm:v1.10.0@%s\n' "$crds_sum"
  } >"$dir/local/tasks/local.yml"
  printf 'render eg-crds\nchart:oci://docker.io/envoyproxy/gateway-crds-helm@%s\noptions:--set crds.envoyGateway.enabled=true --set crds.gatewayAPI.enabled=false\n' \
    "$crds_sum" >"$dir/local/vendor/envoy-gateway/gateway-crds-helm.yaml"
  printf 'render eg\nchart:oci://docker.io/envoyproxy/gateway-helm@%s\noptions:-n envoy-gateway-system --set crds.enabled=false --set global.images.envoyGateway.image=%s --set config.envoyGateway.provider.kubernetes.watch.type=Namespaces --set config.envoyGateway.provider.kubernetes.watch.namespaces={envoy-gateway-system,shop}\n' \
    "$chart_sum" "$controller_ref" >"$dir/local/vendor/envoy-gateway/gateway-helm.yaml"
}

# run_script GOLDEN: runs the script with the stand-in helm first on PATH,
# output in $workdir/out, status in $status.
run_script() {
  status=0
  # The shared_types.go of the controller tag, as the script would fetch it
  # (api/v1alpha1/shared_types.go): the comment line carries no "=", the
  # constant does.
  printf 'const (\n\t// DefaultEnvoyProxyImage is the default image used by envoyproxy\n\tDefaultEnvoyProxyImage = "%s"\n)\n' \
    "${DEFAULT_PROXY_IMAGE:-$proxy_ref}" >"$workdir/shared_types.go"
  PATH="$here/fakes:$PATH" HELM_VERSION="${HELM_VERSION:-v4.3.2}" \
    ENVOY_SHARED_TYPES_FILE="${SHARED_TYPES_FILE:-$workdir/shared_types.go}" \
    bash "$script" "$1" >"$workdir/out" 2>&1 || status=$?
}

# expect_pass NAME GOLDEN
expect_pass() {
  run_script "$2"
  if [ "$status" -ne 0 ]; then
    failures=$((failures + 1))
    printf 'FAIL %s: exit %d, wanted 0\n' "$1" "$status"
    sed 's/^/  /' "$workdir/out"
  else
    printf 'ok   %s\n' "$1"
  fi
}

# expect_fail NAME GOLDEN TEXT: exit non-zero, and TEXT in the output.
expect_fail() {
  run_script "$2"
  if [ "$status" -eq 0 ]; then
    failures=$((failures + 1))
    printf 'FAIL %s: accepted, wanted a refusal\n' "$1"
  elif ! grep -F -q -e "$3" "$workdir/out"; then
    failures=$((failures + 1))
    printf 'FAIL %s: refused, but no message holds: %s\n' "$1" "$3"
    sed 's/^/  /' "$workdir/out"
  else
    printf 'ok   %s\n' "$1"
  fi
}

new_golden "$workdir/good"
expect_pass "an identical render is accepted" "$workdir/good"

new_golden "$workdir/edited-chart"
printf '# edited by hand\n' >>"$workdir/edited-chart/local/vendor/envoy-gateway/gateway-helm.yaml"
expect_fail "an edited controller render is refused" "$workdir/edited-chart" "gateway-helm.yaml"

new_golden "$workdir/edited-crds"
printf '# edited by hand\n' >>"$workdir/edited-crds/local/vendor/envoy-gateway/gateway-crds-helm.yaml"
expect_fail "an edited CRD render is refused" "$workdir/edited-crds" "gateway-crds-helm.yaml"

new_golden "$workdir/missing"
rm "$workdir/missing/local/vendor/envoy-gateway/gateway-helm.yaml"
expect_fail "a missing vendored render is refused" "$workdir/missing" "gateway-helm.yaml"

new_golden "$workdir/other-registry"
sed 's#docker.io/envoyproxy/gateway-helm#evil.invalid/envoyproxy/gateway-helm#' \
  "$workdir/other-registry/local/tasks/local.yml" >"$workdir/local.yml.new"
mv "$workdir/local.yml.new" "$workdir/other-registry/local/tasks/local.yml"
expect_fail "a chart from another registry is refused" "$workdir/other-registry" "ENVOY_GATEWAY_HELM_IMAGE"

new_golden "$workdir/no-digest"
sed 's#@sha256:[0-9a-f]*$##' "$workdir/no-digest/local/tasks/local.yml" >"$workdir/local.yml.new"
mv "$workdir/local.yml.new" "$workdir/no-digest/local/tasks/local.yml"
expect_fail "a reference without a digest is refused" "$workdir/no-digest" "ENVOY_GATEWAY"

new_golden "$workdir/no-namespace"
rm "$workdir/no-namespace/k8s/base/namespace.yaml"
expect_fail "a golden repo without the namespace of the application is refused" "$workdir/no-namespace" "namespace.yaml is missing"

new_golden "$workdir/bad-namespace"
printf 'metadata:\n  name: "Shop;x"\n' >"$workdir/bad-namespace/k8s/base/namespace.yaml"
expect_fail "a namespace that is not a name is refused" "$workdir/bad-namespace" "a namespace name is expected"

new_golden "$workdir/other-namespace"
printf 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: other\n' >"$workdir/other-namespace/k8s/base/namespace.yaml"
expect_fail "a render that watches another namespace is refused" "$workdir/other-namespace" "gateway-helm.yaml"

# The image of the proxy that local/platform/envoy-proxy.yaml pins takes
# precedence over the default compiled in the controller (ADR-005, complement
# of 2026-11-26). A controller moved without the proxy would keep the old
# Envoy, and nothing else shows it: the reference of the file must be the
# DefaultEnvoyProxyImage of shared_types.go at the tag of the controller.
new_golden "$workdir/old-proxy"
newer="docker.io/envoyproxy/envoy:distroless-v1.41.0@sha256:1111111111111111111111111111111111111111111111111111111111111111"
DEFAULT_PROXY_IMAGE="$newer"
expect_fail "a proxy older than the default of the controller is refused" "$workdir/old-proxy" "$proxy_ref"
expect_fail "the message names the default of the controller too" "$workdir/old-proxy" "$newer"
expect_fail "the message names DefaultEnvoyProxyImage" "$workdir/old-proxy" "DefaultEnvoyProxyImage"
unset DEFAULT_PROXY_IMAGE

new_golden "$workdir/same-tag-other-digest"
sed 's#@sha256:09ca[0-9a-f]*#@sha256:2222222222222222222222222222222222222222222222222222222222222222#' \
  "$workdir/same-tag-other-digest/local/platform/envoy-proxy.yaml" >"$workdir/proxy.new"
mv "$workdir/proxy.new" "$workdir/same-tag-other-digest/local/platform/envoy-proxy.yaml"
expect_fail "the same tag with another digest is refused" "$workdir/same-tag-other-digest" "DefaultEnvoyProxyImage"

new_golden "$workdir/no-proxy-file"
rm "$workdir/no-proxy-file/local/platform/envoy-proxy.yaml"
expect_fail "a golden repo without envoy-proxy.yaml is refused" "$workdir/no-proxy-file" "envoy-proxy.yaml"

new_golden "$workdir/no-proxy-image"
printf 'spec:\n  provider:\n    type: Kubernetes\n' >"$workdir/no-proxy-image/local/platform/envoy-proxy.yaml"
expect_fail "an EnvoyProxy without image is refused" "$workdir/no-proxy-image" "pins no proxy image"

new_golden "$workdir/no-constant"
printf 'package v1alpha1\n' >"$workdir/empty_types.go"
SHARED_TYPES_FILE="$workdir/empty_types.go"
expect_fail "a shared_types.go without the constant is refused" "$workdir/no-constant" "DefaultEnvoyProxyImage"
unset SHARED_TYPES_FILE

old_version="${HELM_VERSION:-}"
HELM_VERSION="v4.0.0"
expect_fail "another Helm than the pinned one is refused" "$workdir/good" "HELM_VERSION"
HELM_VERSION="$old_version"

if [ "$failures" -gt 0 ]; then
  printf '%d failure(s)\n' "$failures"
  exit 1
fi
