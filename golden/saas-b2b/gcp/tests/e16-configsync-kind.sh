#!/usr/bin/env bash
# control: E16
# carries: FR-012; ADR-010, conditions 3, 5 and 6; ADR-008, condition 9; ADR-007, condition 5
#
# The gcp layer on kind, with Config Sync in its open source form at the
# version that GKE runs (spec 001, T132; plan, matrix E16). A runner of x64:
# the images of Config Sync are published for linux/amd64 only (ADR-010).
# What it shows, in this order:
# 1. the manifest of Config Sync, vendored with its sum (S32) and with each image
#    written by digest, installs and starts;
# 2. the bootstrap of the layer (gcp/k8s/bootstrap: namespace, roles, admission
#    rule and RootSync) applies, and the RootSync, whose source alone is pointed at
#    the commit under test, reads gcp/k8s/prod, renders it and syncs it: the
#    binding, the render;
# 3. the roleRefs bind the reconciler to the two roles of the layer and to nothing
#    else: no cluster-admin, no write in another namespace, no create of an
#    admission policy, and the writes by name that the layer gives it;
# 4. Config Sync takes over the admission policy and its binding, which the user
#    created with the bootstrap and it did not, and updates them by name: a
#    change made by hand to the policy is put back (tasks.md, gap 168);
# 5. the rule refuses a pod without requests in the namespace of the application
#    and lets the same pod through with them, and leaves other namespaces alone
#    (ADR-008, condition 9; the server decides, `apply --dry-run=server`).
#
# It touches nothing but a kind cluster of its own, in a kubeconfig of its own:
# every kubectl call names both, the context must be that of a kind cluster and
# the server on the loopback, or the test stops before it applies anything
# (principle X: no cluster of GKE is ever reachable from here).
#
# The cluster reads the commit from the Git host (E16_REPO, E16_REVISION), so
# the commit has to be pushed. The defaults are those of the CI of CELIAN: the
# repository GITHUB_REPOSITORY, the commit of the pull request, read anonymously
# over HTTPS (spec.git.auth none; the repository is public).
#
# Stand-ins are applied for what this repository cannot pin: the CRD of
# SecretProviderClass and of SecretSync (tests/e16/stub-crds.yaml), and the CRDs
# of Gateway API of the local layer (v1.7.0, a superset of what GKE serves, for
# the objects to apply: S08 holds the schemas of the version of GKE).
set -uo pipefail

here="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(CDPATH='' cd -- "$here/../.." && pwd)"
CDPATH='' cd -- "$root" || exit 2

for tool in kind kubectl jq git; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "E16: $tool is not on PATH." >&2
    exit 1
  fi
done

name="gcp-e16-$$"
context="kind-$name"
work="$(mktemp -d)" || exit 2
kubeconfig="$work/kubeconfig"
failures=0
cluster_created=0

cleanup() {
  if [ "$cluster_created" -eq 1 ]; then
    kind delete cluster --name "$name" --kubeconfig "$kubeconfig" >/dev/null 2>&1 || echo "E16: kind delete cluster $name failed: check kind get clusters." >&2
  fi
  rm -rf "${work:?}"
}
trap cleanup EXIT

# Every call to the cluster names the kubeconfig and the context.
k() {
  kubectl --kubeconfig "$kubeconfig" --context "$context" "$@"
}

fail() {
  failures=$((failures + 1))
  printf 'E16 | FR-012: %s\n' "$1" >&2
}

die() {
  fail "$1"
  diagnostics
  exit 1
}

diagnostics() {
  [ "$cluster_created" -eq 1 ] || return 0
  echo "--- RootSync: errors of the source, the rendering and the sync ---" >&2
  k -n config-management-system get rootsync root-sync -o json 2>&1 |
    jq '{source: .status.source.errors, rendering: .status.rendering.errors, sync: .status.sync.errors, conditions: [.status.conditions[]? | {type, status, message, errorSummary}]}' 2>&1 | head -c 6000 >&2
  echo >&2
  echo "--- the objects of the ResourceGroup that are not Current ---" >&2
  k -n config-management-system get resourcegroups root-sync -o json 2>&1 |
    jq -c '.status.resourceStatuses[]? | select(.status != "Current") | {kind, name, namespace, status, actuation, reconcile}' 2>&1 | head -20 >&2
  echo "--- pods of config-management-system ---" >&2
  k -n config-management-system get pods 2>&1 | head -20 >&2
  echo "--- reconciler log ---" >&2
  k -n config-management-system logs deployment/root-reconciler -c reconciler --tail=400 2>&1 |
    grep -i -E 'error|fail|forbidden|denied|unable' | tail -30 | cut -c1-400 >&2
}

# Waits up to $1 seconds for the command that follows to succeed.
wait_for() {
  local limit="$1" waited=0
  shift
  until "$@" >/dev/null 2>&1; do
    waited=$((waited + 5))
    [ "$waited" -le "$limit" ] || return 1
    sleep 5
  done
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

# --- The commit under test ------------------------------------------------------

repo="${E16_REPO:-}"
if [ -z "$repo" ] && [ -n "${GITHUB_REPOSITORY:-}" ]; then
  repo="https://github.com/$GITHUB_REPOSITORY.git"
fi
revision="${E16_REVISION:-$(git rev-parse HEAD 2>/dev/null)}"
prefix="$(git rev-parse --show-prefix 2>/dev/null)"
dir="${E16_DIR:-${prefix}gcp/k8s/prod}"
sync_timeout="${E16_SYNC_TIMEOUT:-900}"
if [ -z "$repo" ] || [ -z "$revision" ]; then
  echo "E16: set E16_REPO (an https URL that the cluster reads) and E16_REVISION (a pushed commit)." >&2
  exit 1
fi
case "$repo" in
  https://*) ;;
  *)
    echo "E16: E16_REPO is $repo: an https URL is expected, read without a credential." >&2
    exit 1
    ;;
esac

# --- The vendored files -----------------------------------------------------------

bash gcp/tests/static/s32-vendor-sums.sh >/dev/null || die "S32 fails: the manifest of Config Sync is not the vendored one."
gateway_crds="local/vendor/gateway-api/standard-install.yaml"
want="$(awk -v f="gateway-api/standard-install.yaml" '$2 == f { print $1 }' local/vendor/SHA256SUMS)"
[ -n "$want" ] && [ "$(sha256_of "$gateway_crds")" = "$want" ] || die "$gateway_crds does not match local/vendor/SHA256SUMS."

# The manifest with each image written by digest, reconciler templates included:
# the lines "image: <reference>" are the only place the manifest names one.
manifest="gcp/vendor/config-sync/config-sync-manifest.yaml"
images="gcp/vendor/config-sync/images"
awk '
  FNR == NR { if ($1 !~ /^#/ && NF == 2) digest[$1] = $2; next }
  $1 == "image:" && NF == 2 && ($2 in digest) { sub($2 "$", $2 "@" digest[$2]) }
  { print }
' "$images" "$manifest" >"$work/config-sync.yaml"
if grep -E '^[[:space:]]*image:[[:space:]]+[^[:space:]]+$' "$work/config-sync.yaml" | grep -v -q '@sha256:' ; then
  grep -E '^[[:space:]]*image:[[:space:]]+[^[:space:]]+$' "$work/config-sync.yaml" | grep -v '@sha256:' >&2
  die "the manifest of Config Sync still names an image by tag (ADR-010, condition 6)."
fi

# --- The cluster -------------------------------------------------------------------

node_image="$(awk '$1 == "image:" && $2 ~ /^kindest\/node:/ { print $2; exit }' local/kind/cluster.yaml)"
[ -n "$node_image" ] || die "local/kind/cluster.yaml names no node image."
kind create cluster --name "$name" --image "$node_image" --kubeconfig "$kubeconfig" --wait 180s >"$work/kind.log" 2>&1 || {
  cat "$work/kind.log" >&2
  cluster_created=1
  die "kind create cluster failed."
}
cluster_created=1
server="$(k config view --minify -o 'jsonpath={.clusters[0].cluster.server}')"
case "$context:$server" in
  kind-gcp-e16-*:https://127.0.0.1:*) ;;
  *) die "the context $context reaches $server: E16 stops, it only touches a kind cluster on the loopback." ;;
esac

# --- 1. Config Sync, the stand-ins -------------------------------------------------

k apply --server-side -f "$gateway_crds" >/dev/null || die "the CRDs of Gateway API do not apply."
k apply -f "$here/e16/stub-crds.yaml" >/dev/null || die "the stand-in CRDs do not apply."
k apply --server-side --force-conflicts -f "$work/config-sync.yaml" >/dev/null || die "the manifest of Config Sync does not apply."
wait_for 600 k -n config-management-system rollout status deployment/reconciler-manager --timeout=5s ||
  die "reconciler-manager does not become available."
wait_for 600 k -n resource-group-system rollout status deployment/resource-group-controller-manager --timeout=5s ||
  die "resource-group-controller-manager does not become available."

# --- 2. The bootstrap and the RootSync ----------------------------------------------

k apply -k gcp/k8s/bootstrap >/dev/null || die "the bootstrap of the layer does not apply."
patch="$(printf '{"spec":{"git":{"repo":"%s","revision":"%s","dir":"%s","auth":"none","secretRef":null}}}' "$repo" "$revision" "$dir")"
k -n config-management-system patch rootsync root-sync --type merge -p "$patch" >/dev/null || die "the RootSync does not take the source of the test."

synced() {
  local commit
  commit="$(k -n config-management-system get rootsync root-sync -o 'jsonpath={.status.sync.commit}')"
  [ "$commit" = "$revision" ] &&
    [ -z "$(k -n config-management-system get rootsync root-sync -o 'jsonpath={.status.sync.errors}{.status.rendering.errors}{.status.source.errors}')" ]
}
wait_for "$sync_timeout" synced || die "the RootSync does not sync $revision of $repo, dir $dir, in ${sync_timeout} s."
echo "E16: the RootSync synced $revision from $dir."

for object in gateway/saas-b2b configmap/app-config configmap/app-ca deployment/api deployment/front serviceaccount/secret-sync; do
  k -n saas-b2b get "$object" >/dev/null 2>&1 || fail "$object of the render is not in the namespace saas-b2b after the sync."
done
class="$(k -n saas-b2b get gateway saas-b2b -o 'jsonpath={.spec.gatewayClassName}')"
[ "$class" = "gke-l7-global-external-managed" ] || fail "the Gateway synced asks the class $class, gke-l7-global-external-managed expected."

# --- 3. The rights of the reconciler -------------------------------------------------

reconciler="system:serviceaccount:config-management-system:root-reconciler"
can() {
  # $1 wanted answer, the rest are the arguments of kubectl auth can-i
  local want="$1" got
  shift
  got="$(k auth can-i "$@" --as="$reconciler" 2>/dev/null)"
  [ "$got" = "$want" ] || fail "the reconciler: can-i $* answers '$got', '$want' expected (ADR-010, condition 3)."
}
can yes create deployments.apps -n saas-b2b
can yes update configmaps -n saas-b2b
can no create deployments.apps -n default
can no delete deployments.apps -n default
can no create configmaps -n kube-system
can no create secrets -n saas-b2b
can no create roles.rbac.authorization.k8s.io -n saas-b2b
can no create clusterroles.rbac.authorization.k8s.io
can no create validatingadmissionpolicies.admissionregistration.k8s.io
can no create validatingadmissionpolicybindings.admissionregistration.k8s.io
can no create namespaces
can no delete namespaces
can yes patch namespaces/saas-b2b
can yes update validatingadmissionpolicies.admissionregistration.k8s.io/saas-b2b-require-requests
can yes list deployments.apps
can yes list secretsyncs.secret-sync.gke.io
can no patch deployments.apps
can no list secrets
can no list secrets -n saas-b2b
can no list pods
can yes list pods -n saas-b2b
can no create pods -n saas-b2b
can no '*' '*'
admin_bindings="$(k get clusterrolebindings,rolebindings -A -o json | jq -r --arg sa "root-reconciler" '
  [.items[] | select(.roleRef.name == "cluster-admin") | select(any(.subjects[]?; .name == $sa))] | length')"
[ "$admin_bindings" = "0" ] || fail "a binding to cluster-admin names the reconciler: $admin_bindings found (ADR-010, condition 3)."

# --- 4. The admission objects, taken over and updated by name --------------------------

policy="saas-b2b-require-requests"
resource_status() {
  k -n config-management-system get resourcegroups root-sync -o json 2>/dev/null |
    jq -r --arg kind "$1" --arg name "$2" '[.status.resourceStatuses[]? | select(.kind == $kind and .name == $name) | .status] | first // ""'
}
is_current() {
  [ "$(resource_status "$1" "$2")" = Current ]
}
for kind_name in ValidatingAdmissionPolicy ValidatingAdmissionPolicyBinding; do
  wait_for 120 is_current "$kind_name" "$policy" ||
    fail "$kind_name $policy is not Current in the ResourceGroup of the RootSync: Config Sync did not take over the object that the bootstrap created."
done

k patch validatingadmissionpolicy "$policy" --type merge -p '{"spec":{"failurePolicy":"Ignore"}}' >/dev/null || fail "the test cannot change the policy by hand."
put_back() {
  [ "$(k get validatingadmissionpolicy "$policy" -o 'jsonpath={.spec.failurePolicy}')" = Fail ]
}
wait_for 180 put_back || fail "Config Sync does not put back the policy changed by hand: it cannot update by name an object that it did not create (tasks.md, gap 168)."

# --- 5. A pod without requests is refused ------------------------------------------------

pod() {
  # $1 namespace, $2 the resources of the container, as JSON
  printf '{"apiVersion":"v1","kind":"Pod","metadata":{"name":"e16-probe","namespace":"%s"},"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"c","image":"probe.invalid/c:1","resources":%s,"securityContext":{"allowPrivilegeEscalation":false,"readOnlyRootFilesystem":true,"capabilities":{"drop":["ALL"]}}}]}}' "$1" "$2"
}
no_requests='{"limits":{"memory":"64Mi"}}'
with_requests='{"requests":{"cpu":"10m","memory":"16Mi"},"limits":{"memory":"64Mi"}}'

# The binding takes a moment to be served by the API server.
refused() {
  pod saas-b2b "$no_requests" | k apply --dry-run=server -f - 2>&1 | grep -q "$policy"
}
if wait_for 120 refused; then
  echo "E16: a pod without requests is refused in saas-b2b by $policy."
else
  out="$(pod saas-b2b "$no_requests" | k apply --dry-run=server -f - 2>&1)"
  fail "a pod without requests is not refused by $policy in saas-b2b (ADR-008, condition 9): $out"
fi
out="$(pod saas-b2b "$with_requests" | k apply --dry-run=server -f - 2>&1)" || fail "a pod with requests is refused in saas-b2b: $out"
out="$(pod default "$no_requests" | k apply --dry-run=server -f - 2>&1)" || fail "a pod without requests is refused in the namespace default, which the binding does not select: $out"

if [ "$failures" -gt 0 ]; then
  diagnostics
  printf 'E16: %s failure(s).\n' "$failures" >&2
  exit 1
fi
echo "E16: the gcp layer syncs on kind, the reconciler is bound to its two roles, and the admission rule refuses a pod without requests."
