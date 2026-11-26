#!/usr/bin/env bash
# Redoes the render of Envoy Gateway from the OCI artifacts that
# golden/saas-b2b/local/tasks/local.yml names by digest, and compares it byte
# for byte with the files of local/vendor/envoy-gateway/ (spec 001, tasks.md,
# gap 44). Without it, a render edited by hand and a SHA256SUMS redone pass
# S02 and S22, which compare the vendored files to themselves and to
# references.
#
# The commands and options are those of research RS-02, "Relevé du
# 2026-11-25: Gateway API et Envoy Gateway vendorés", with the watch of the
# controller of its "Relevé du 2026-11-25 : périmètre du contrôleur
# d'Envoy Gateway" (ADR-005, complement of 2026-11-25):
#   helm template eg-crds <crds chart> \
#     --set crds.envoyGateway.enabled=true --set crds.gatewayAPI.enabled=false
#   helm template eg <chart> -n envoy-gateway-system --set crds.enabled=false \
#     --set global.images.envoyGateway.image=<controller image by digest> \
#     --set config.envoyGateway.provider.kubernetes.watch.type=Namespaces \
#     --set 'config.envoyGateway.provider.kubernetes.watch.namespaces={envoy-gateway-system,<application>}'
# <application> is the namespace of the application, the name of
# k8s/base/namespace.yaml of the golden repo.
# Each chart is pulled by digest, so what Helm renders is the artifact that
# the reference names. Helm runs with its cache, config and data in a
# temporary folder, without any registry login.
#
# HELM_VERSION, when set, must be the version of the helm on PATH: the
# workflow pins it, with the sum of the archive that
# scripts/ci/install-helm.sh checks.
#
# Usage: scripts/ci/check-envoy-gateway-render.sh [<golden repo>]
# The golden repo defaults to golden/saas-b2b/.
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
golden="${1:-$root/golden/saas-b2b}"
tasks_file="$golden/local/tasks/local.yml"
vendor="$golden/local/vendor/envoy-gateway"
namespace_file="$golden/k8s/base/namespace.yaml"
# The namespace of the controller, which the watch always names.
readonly CONTROLLER_NAMESPACE="envoy-gateway-system"

die() {
  echo "check-envoy-gateway-render.sh: $1" >&2
  exit 1
}

command -v helm >/dev/null 2>&1 || die "helm is not on PATH: run scripts/ci/install-helm.sh <directory>."
[ -f "$tasks_file" ] || die "$tasks_file is missing: it holds the references of the three artifacts."

helm_version="$(helm version --template '{{.Version}}')"
if [ -n "${HELM_VERSION:-}" ] && [ "$helm_version" != "$HELM_VERSION" ]; then
  die "helm is $helm_version, and HELM_VERSION pins $HELM_VERSION."
fi

# ref_of NAME: the value of the variable NAME of local.yml.
ref_of() {
  awk -v name="$1:" '$1 == name { print $2; exit }' "$tasks_file"
}

# checked_ref NAME REPOSITORY: the reference of variable NAME, refused unless
# it is docker.io/envoyproxy/REPOSITORY, a tag, and a SHA-256 digest.
checked_ref() {
  local name="$1" repository="$2" ref
  ref="$(ref_of "$name")"
  [[ $ref =~ ^docker\.io/envoyproxy/${repository}:v[0-9][^@[:space:]]*@sha256:[0-9a-f]{64}$ ]] ||
    die "$name in $tasks_file is \"$ref\": it must be docker.io/envoyproxy/$repository:<tag>@sha256:<digest>."
  printf '%s\n' "$ref"
}

controller_ref="$(checked_ref ENVOY_GATEWAY_IMAGE gateway)"
chart_ref="$(checked_ref ENVOY_GATEWAY_HELM_IMAGE gateway-helm)"
crds_ref="$(checked_ref ENVOY_GATEWAY_CRDS_HELM_IMAGE gateway-crds-helm)"

# The namespace of the application, which the controller watches with its
# own: the first name: of k8s/base/namespace.yaml, metadata.name.
[ -f "$namespace_file" ] || die "$namespace_file is missing: it names the namespace of the application, which the controller watches."
app_namespace="$(awk '$1 == "name:" { print $2; exit }' "$namespace_file")"
[[ $app_namespace =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] ||
  die "the name of $namespace_file is \"$app_namespace\": a namespace name is expected."

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
export HELM_CACHE_HOME="$workdir/helm-cache"
export HELM_CONFIG_HOME="$workdir/helm-config"
export HELM_DATA_HOME="$workdir/helm-data"
mkdir -p "$workdir/render"

# pull_chart REF DIR: pulls the artifact REF by digest into DIR, prints the
# path of the archive.
pull_chart() {
  local ref="$1" dir="$2" repository digest archive
  repository="${ref%%:*}"
  digest="${ref##*@}"
  mkdir -p "$dir"
  helm pull "oci://$repository@$digest" --destination "$dir" >/dev/null ||
    die "helm pull of oci://$repository@$digest failed."
  archive="$(find "$dir" -type f -name '*.tgz' | head -n 1)"
  [ -n "$archive" ] || die "helm pull of oci://$repository@$digest left no archive."
  printf '%s\n' "$archive"
}

echo "helm $helm_version, rendering Envoy Gateway from the artifacts of $tasks_file"

crds_archive="$(pull_chart "$crds_ref" "$workdir/pull/crds")"
helm template eg-crds "$crds_archive" \
  --set crds.envoyGateway.enabled=true --set crds.gatewayAPI.enabled=false \
  >"$workdir/render/gateway-crds-helm.yaml" || die "helm template of the CRD chart failed."

chart_archive="$(pull_chart "$chart_ref" "$workdir/pull/chart")"
helm template eg "$chart_archive" -n "$CONTROLLER_NAMESPACE" --set crds.enabled=false \
  --set "global.images.envoyGateway.image=$controller_ref" \
  --set config.envoyGateway.provider.kubernetes.watch.type=Namespaces \
  --set "config.envoyGateway.provider.kubernetes.watch.namespaces={$CONTROLLER_NAMESPACE,$app_namespace}" \
  >"$workdir/render/gateway-helm.yaml" || die "helm template of the controller chart failed."

failures=0
for file in gateway-crds-helm.yaml gateway-helm.yaml; do
  if [ ! -f "$vendor/$file" ]; then
    echo "$vendor/$file is missing: the render of $file has nothing to be compared with." >&2
    failures=$((failures + 1))
  elif cmp -s "$workdir/render/$file" "$vendor/$file"; then
    echo "ok   $file is the render of its artifact, byte for byte."
  else
    echo "FAIL $vendor/$file differs from the render of its artifact; first differences:" >&2
    { diff -u "$vendor/$file" "$workdir/render/$file" | head -n 20 >&2; } || true
    failures=$((failures + 1))
  fi
done

[ "$failures" -eq 0 ]
