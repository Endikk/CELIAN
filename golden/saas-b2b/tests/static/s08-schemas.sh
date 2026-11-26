#!/usr/bin/env bash
# control: S08
# carries: FR-010; ADR-005, condition 5; research RS-16 and RS-18
#
# The rendered manifests are valid against their schemas, and the Gateway and
# the HTTPRoutes against the schema of the Gateway API that GKE serves
# (ADR-005, condition 5): kubeconform, offline, on the schemas of
# tests/schemas/.
# - tests/schemas/SHA256SUMS lists every schema and each sum matches: the
#   schemas are versioned, checked, and never fetched (regenerate.sh says
#   where they come from);
# - the Kustomize render of k8s/base, of every overlay of k8s/overlays/ and
#   of the Kubernetes folders of the gcp layer (gcp/k8s/prod, bootstrap and
#   values) passes `kubeconform -strict`: a field that the schema does not
#   list is refused, which is what keeps the common layer to the fields of
#   the Gateway API that GKE serves (v1.5.0 from GKE 1.35.2-gke.1842000, page
#   of GKE read on 2026-11-26);
# - a kind without a schema fails, and is added to KUBERNETES_FILES in
#   tests/schemas/regenerate.sh. Three kinds of GKE and of Config Sync have
#   no schema that this repo could pin: SecretProviderClass and SecretSync
#   (no published CRD that was read), RootSync (the CRD is in the manifest of
#   Config Sync, vendored by T132). They are skipped here by name, and
#   S31 and S10 read their fields instead (tasks.md, gap 149);
# - the check is proved on the schemas themselves: the Gateway of the common
#   layer with a field the schema lacks, and with a port written as text, is
#   refused.
# The local renders (local/k8s/) are not validated yet: their kinds
# (StatefulSet, Job) have no schema here (tasks.md, gap 149).
set -uo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
CDPATH='' cd -- "$root" || exit 2

for tool in kubeconform kubectl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is not on PATH: S08 renders with kubectl kustomize and validates with kubeconform (tests/tools/install.sh installs the second)." >&2
    exit 1
  fi
done

schemas="tests/schemas"
sums_file="$schemas/SHA256SUMS"
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

# --- The schemas and their sums ------------------------------------------------

if [ ! -f "$sums_file" ]; then
  echo "$sums_file is missing: the schemas of S08 are not written yet (spec 001, T130)." >&2
  exit 1
fi

listed="$(awk '{ print $2 }' "$sums_file" | LC_ALL=C sort)"
present="$(CDPATH='' cd -- "$schemas" && find gateway-api kubernetes -type f -name '*.json' | LC_ALL=C sort)"
if [ "$listed" != "$present" ]; then
  fail "$sums_file and the schemas differ: listed [$(printf '%s' "$listed" | tr '\n' ' ')], present [$(printf '%s' "$present" | tr '\n' ' ')]."
fi
while read -r sum file; do
  [ -f "$schemas/$file" ] || continue
  if [ "$(sha256_of "$schemas/$file")" != "$sum" ]; then
    fail "$schemas/$file does not match its SHA-256 in $sums_file: run tests/schemas/regenerate.sh and read the diff."
  fi
done <"$sums_file"
if [ "$failures" -gt 0 ]; then
  exit 1
fi

# --- The renders ----------------------------------------------------------------

work="$(mktemp -d)" || exit 2
trap 'rm -rf "${work:?}"' EXIT

dirs="k8s/base"
for dir in k8s/overlays/*/; do
  dirs="$dirs ${dir%/}"
done
for dir in k8s/overlays/staging k8s/overlays/prod gcp/k8s/prod gcp/k8s/bootstrap gcp/k8s/values; do
  if [ ! -f "$dir/kustomization.yaml" ]; then
    echo "$dir/kustomization.yaml is missing: the prod and staging overlays (T133) and the gcp layer (T134) are not written yet." >&2
    exit 1
  fi
done
dirs="$dirs gcp/k8s/prod gcp/k8s/bootstrap gcp/k8s/values"

validate() {
  # $1 file, the rest are extra kubeconform options
  local file="$1"
  shift
  kubeconform -strict -summary \
    -schema-location "$schemas/kubernetes/{{.ResourceKind}}{{.KindSuffix}}.json" \
    -schema-location "$schemas/gateway-api/{{.ResourceKind}}{{.KindSuffix}}.json" \
    "$@" "$file"
}

skipped="SecretProviderClass,SecretSync,RootSync"
rendered=0
for dir in $dirs; do
  name="$(printf '%s' "$dir" | tr '/' '-')"
  if ! kubectl kustomize "$dir" >"$work/$name.yaml" 2>"$work/$name.err"; then
    fail "kubectl kustomize $dir failed: $(cat "$work/$name.err")"
    continue
  fi
  rendered=$((rendered + 1))
  if ! out="$(validate "$work/$name.yaml" -skip "$skipped" 2>&1)"; then
    fail "$dir does not validate against the schemas of $schemas/ (a kind without a schema is added to tests/schemas/regenerate.sh):"
    fail "$(printf '%s\n' "$out" | sed -e "s#$work/##")"
  fi
done

# --- The check proves itself ------------------------------------------------------

gateway="$work/k8s-base.yaml"
awk '{ print } /^  gatewayClassName:/ { print "  fieldFromAnotherVersion: true" }' "$gateway" >"$work/extra-field.yaml"
if validate "$work/extra-field.yaml" -skip "$skipped" >/dev/null 2>&1; then
  fail "S08 accepts a Gateway with a field that the schema of Gateway API lacks: the schemas are not strict."
fi
# kubectl kustomize sorts the keys: the port of the listener is the line
# "    port: 80" at four spaces, the ports of the routes sit deeper.
awk '/^    port: 80$/ { print "    port: eighty"; next } { print }' "$gateway" >"$work/text-port.yaml"
if validate "$work/text-port.yaml" -skip "$skipped" >/dev/null 2>&1; then
  fail "S08 accepts a Gateway whose port is a text: the schemas do not check types."
fi

if [ "$failures" -gt 0 ]; then
  exit 1
fi
echo "$rendered render(s) validate against the schemas of $schemas/ ($skipped skipped by name)."
