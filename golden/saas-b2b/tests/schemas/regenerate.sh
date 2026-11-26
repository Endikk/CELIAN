#!/usr/bin/env bash
# Rewrites the JSON schemas of tests/schemas/ and their SHA256SUMS. A person
# runs it when a version below moves, with the gh CLI logged in, conftest and
# jq on PATH, and reads the diff in the pull request; no test runs it
# (research RS-18, "Schémas de S08"). S08 checks the sums and never fetches.
#
# - gateway-api/: the CRDs Gateway, GatewayClass and HTTPRoute (version v1)
#   of the standard channel of Gateway API at the version that GKE serves
#   (page "GatewayClass capabilities" of GKE, research RS-16). The CRD file is
#   the release asset standard-install.yaml, checked against its SHA-256
#   before use; the schema of a kind is the openAPIV3Schema of its CRD.
# - kubernetes/: the "standalone-strict" schemas that the author of
#   kubeconform publishes (github.com/yannh/kubernetes-json-schema, which
#   kubeconform names its default source), for the minor of platform.yaml, at
#   one commit written below, never at a branch.
#
# Usage: tests/schemas/regenerate.sh
set -euo pipefail

GATEWAY_API_VERSION="v1.5.0"
# SHA-256 of standard-install.yaml of that release, read on 2026-11-26 in the
# digest field of the API of the releases and in the file itself.
GATEWAY_RELEASE_SHA256="510338cf6709f84410efcce5269268f4c7c5067efdc5d04c75aa2fd2f8380c96"
GATEWAY_KINDS="Gateway GatewayClass HTTPRoute"

SCHEMA_REPO="yannh/kubernetes-json-schema"
SCHEMA_COMMIT="e62c03bd5a52fd34ff6ac28d083e2a300e0ae7c1"
SCHEMA_DIR="v1.36.7-standalone-strict"
# One file for each kind that the renders of the common layer and of the gcp
# layer hold, named as kubeconform names it: <kind>-<group>-<version>, or
# <kind>-<version> for the core group. A kind that a later step adds is
# written here, then the script is run again.
KUBERNETES_FILES="namespace-v1 configmap-v1 serviceaccount-v1 service-v1 deployment-apps-v1 networkpolicy-networking-v1 role-rbac-v1 rolebinding-rbac-v1 clusterrole-rbac-v1 validatingadmissionpolicy-admissionregistration-v1 validatingadmissionpolicybinding-admissionregistration-v1"

here="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

die() {
  echo "regenerate.sh: $1" >&2
  exit 1
}

for tool in gh conftest jq shasum; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not on PATH."
done

work="$(mktemp -d)"
trap 'rm -rf "${work:?}"' EXIT

# Gateway API.
gh release download "$GATEWAY_API_VERSION" -R kubernetes-sigs/gateway-api -p standard-install.yaml -D "$work"
got="$(shasum -a 256 "$work/standard-install.yaml" | awk '{ print $1 }')"
[ "$got" = "$GATEWAY_RELEASE_SHA256" ] || die "standard-install.yaml of $GATEWAY_API_VERSION has the SHA-256 $got, $GATEWAY_RELEASE_SHA256 expected."
conftest parse "$work/standard-install.yaml" >"$work/crds.json"

rm -rf "${here:?}/gateway-api" "${here:?}/kubernetes"
mkdir -p "$here/gateway-api" "$here/kubernetes"
# A CRD schema lets unknown fields through; the API server prunes them. S08
# wants the opposite: a field that this version of Gateway API does not have is
# a field that GKE may not serve (ADR-005, condition 5). Every object that
# lists properties therefore gets additionalProperties: false, unless the CRD
# keeps unknown fields on purpose, as kubeconform does with its own strict
# mode for the schemas that it generates.
for kind in $GATEWAY_KINDS; do
  lower="$(printf '%s' "$kind" | tr '[:upper:]' '[:lower:]')"
  jq -e --arg kind "$kind" '
    def strict:
      walk(
        if type == "object" and has("properties") and (has("additionalProperties") | not)
           and (.["x-kubernetes-preserve-unknown-fields"] != true)
        then . + {additionalProperties: false}
        else . end
      );
    .[] | select(. != null and .kind == "CustomResourceDefinition" and .spec.names.kind == $kind)
    | .spec.versions[] | select(.name == "v1") | .schema.openAPIV3Schema | strict
  ' "$work/crds.json" >"$here/gateway-api/$lower-gateway-v1.json" || die "no v1 schema for $kind in standard-install.yaml."
done

# Kubernetes.
for name in $KUBERNETES_FILES; do
  gh api "repos/$SCHEMA_REPO/contents/$SCHEMA_DIR/$name.json?ref=$SCHEMA_COMMIT" --jq '.content' |
    base64 -d >"$here/kubernetes/$name.json"
  jq -e '.properties.kind' "$here/kubernetes/$name.json" >/dev/null || die "$name.json is not a Kubernetes schema."
done

(
  CDPATH='' cd -- "$here"
  find gateway-api kubernetes -type f -name '*.json' | LC_ALL=C sort | while IFS= read -r file; do
    printf '%s  %s\n' "$(shasum -a 256 "$file" | awk '{ print $1 }')" "$file"
  done >SHA256SUMS
)
echo "tests/schemas/ rewritten: Gateway API $GATEWAY_API_VERSION, Kubernetes schemas of $SCHEMA_DIR at $SCHEMA_COMMIT."
