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

failures=0

# new_golden DIR: a golden repo with the three references, the namespace of
# the application, and the two vendored renders the stand-in helm is
# expected to give: the controller chart with the watch of research RS-02
# (ADR-005, complement of 2026-11-25).
new_golden() {
  local dir="$1"
  mkdir -p "$dir/local/tasks" "$dir/local/vendor/envoy-gateway" "$dir/k8s/base"
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
  PATH="$here/fakes:$PATH" HELM_VERSION="${HELM_VERSION:-v4.3.2}" \
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

old_version="${HELM_VERSION:-}"
HELM_VERSION="v4.0.0"
expect_fail "another Helm than the pinned one is refused" "$workdir/good" "HELM_VERSION"
HELM_VERSION="$old_version"

if [ "$failures" -gt 0 ]; then
  printf '%d failure(s)\n' "$failures"
  exit 1
fi
