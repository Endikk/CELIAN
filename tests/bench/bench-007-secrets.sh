#!/usr/bin/env bash
# BENCH-007: how the generated project hands its secrets to its pods on the
# PC, so that the application manifests stay the same on GCP. Cluster: kind
# (BENCH-003), one fresh single-node cluster per option.
#
# Options:
#   openbao  OpenBao in the cluster, auto-unsealed by a static key generated
#            here, plus External Secrets Operator (ESO) and its vault provider.
#   eso      ESO alone: its kubernetes provider reads a source namespace that
#            this script fills with random values.
#   native   plain Kubernetes Secrets created by this script, no operator.
# In every option the application reads a Secret named app-db, key password.
#
# For each option the script measures:
#   - install time until "ready": option pods ready (OpenBao initialised and
#     unsealed) and its SecretStore Ready; run 0 is cold (fresh node, images
#     pulled from the registry), runs 1..RUNS are warm (images in the node);
#   - injection: time until a busybox pod reads the value through an env var,
#     and whether its SHA-256 matches the value written;
#   - CPU and memory at rest of the option's pods, and of the kube-system
#     pods (API server, etcd), from the kubelet summary API, IDLE_WAIT
#     seconds after "ready" (3 samples, 10 s apart);
#   - restart: RESTARTS times docker stop + docker start of the node
#     container, time until the option is ready again, seal state, value kept;
#   - functional checks (FUNCTIONAL=1): services and ports, access without a
#     token from another namespace, etcd encryption flag, OpenBao with a
#     Shamir seal after a restart, ESO Password generator with CreatedOnce.
#
# Usage: tests/bench/bench-007-secrets.sh [TRIAL_DIR]
#   TRIAL_DIR, if given, must be missing or empty (default: a new mktemp -d).
#   Environment:
#     OPTIONS="openbao eso native"  options, measured in this order
#     RUNS=3         warm runs per option, after the cold run
#     RESTARTS=3     node restarts per option
#     FUNCTIONAL=1   functional checks; 0 to skip them
#     IDLE_WAIT=120  seconds between "ready" and the first idle sample
#     BENCH_LOCK=""  if set, a directory taken with mkdir before measuring and
#                    removed at exit; the script refuses to start if it exists
#     FRESH=0        1: RUNS installs, each on a new cluster (the task up
#                    case), without cold run, restarts nor functional checks
#   Results (TSV) in TRIAL_DIR: versions.tsv, load.tsv, images.tsv, runs.tsv,
#   phases.tsv, idle-samples.tsv, node-images.tsv, restarts.tsv, ports.tsv,
#   functional.tsv, summary.tsv; command output in TRIAL_DIR/logs/.
# Needs: bash >= 3.2, docker, kind, kubectl (1.35 to 1.37), helm 4, gh, jq,
#   perl, shasum, lsof, base64, head, at the versions pinned below.
#
# Safety:
#   - the cluster is named celian-bench-007; the script refuses to start if
#     a container of that cluster exists. Its EXIT trap is set only after the
#     start-up checks and the lock, so a refusal deletes nothing; afterwards
#     it deletes only that cluster, and the "kind" network if it created it
#     and nothing uses it;
#   - umask 077; KUBECONFIG and Helm's directories point into TRIAL_DIR:
#     ~/.kube/config and the user's Helm configuration are not used;
#   - charts are downloaded with gh and used only if their SHA-256 matches;
#     images are pinned by tag and digest;
#   - every secret value is random, disposable, generated here, and piped to
#     kubectl create from printf, never on a command line, in a heredoc or
#     in a file of the PC. etcd keeps it, unencrypted, in the node. Only its
#     SHA-256 is kept. The OpenBao root token is revoked after the setup.
#     The 2026-11-19 series ran an earlier version, which used a heredoc
#     (a temporary file under bash 3.2) and kubectl apply;
#   - no port is published to the host besides the API server of kind,
#     on 127.0.0.1.
# Side effects outside TRIAL_DIR: the kind node image stays in the Docker
# image cache. Nothing else is pulled into the host cache.
set -euo pipefail
umask 077

# --- Pinned versions ----------------------------------------------------------

readonly KIND_VERSION="v0.33.0"
readonly K8S_VERSION="v1.36.4"
readonly KUBECTL_MINORS="35 36 37"
readonly HELM_MAJOR="v4"
# kind v0.33.0 release notes: node images must be used with their digest.
readonly KIND_IMAGE="kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed"
readonly BUSYBOX_IMAGE="busybox:1.37.0@sha256:a7dbc319b1438115a207e11930dc4bb3e643dcb3ec0bdd694bb36cd8fad289ec"

readonly OPENBAO_CHART_REPO="openbao/openbao-helm"
readonly OPENBAO_CHART_TAG="openbao-0.30.7"
readonly OPENBAO_CHART_FILE="openbao-0.30.7.tgz"
readonly OPENBAO_CHART_SHA256="fa4e6f3c1bbe936dc7ba079f1303ea56810af2f8600f046d8d5809860a4f980f"
readonly OPENBAO_APP_VERSION="v2.7.2"
readonly OPENBAO_REGISTRY="quay.io"
readonly OPENBAO_REPOSITORY="openbao/openbao"
readonly OPENBAO_TAG="2.7.2@sha256:5046911075e137e154ce49ab051502f4ec7cf367d484ae4a4dce665d9b90561f"

readonly ESO_CHART_REPO="external-secrets/external-secrets"
readonly ESO_CHART_TAG="helm-chart-2.15.0"
readonly ESO_CHART_FILE="external-secrets-2.15.0.tgz"
readonly ESO_CHART_SHA256="ed94d41cc67e392ea45e370345eb491b0fdc21387f1aaaefcf8e2e6c85089e1d"
readonly ESO_APP_VERSION="v2.15.0"
readonly ESO_REPOSITORY="ghcr.io/external-secrets/external-secrets"
readonly ESO_TAG="v2.15.0@sha256:6888f243e5f8f7592c6d7fae2a5547c9e33531441b47b53807b9093b25a00e31"

readonly CLUSTER="celian-bench-007"
readonly NODE="$CLUSTER-control-plane"
readonly NS_APP="celian-app"
readonly NS_BAO="celian-openbao"
readonly NS_ESO="celian-eso"
readonly NS_SRC="celian-secrets-src"
readonly NS_SHAMIR="celian-openbao-shamir"
readonly BAO_URL="http://openbao.$NS_BAO.svc:8200"
readonly SAMPLES=3
readonly SAMPLE_GAP=10
readonly PAUSE_BETWEEN_RUNS=15
readonly READY_TIMEOUT=900
readonly READY_STREAK=3

OPTIONS="${OPTIONS:-openbao eso native}"
RUNS="${RUNS:-3}"
RESTARTS="${RESTARTS:-3}"
FUNCTIONAL="${FUNCTIONAL:-1}"
IDLE_WAIT="${IDLE_WAIT:-120}"
BENCH_LOCK="${BENCH_LOCK:-}"
FRESH="${FRESH:-0}"
readonly OPTIONS RUNS RESTARTS FUNCTIONAL IDLE_WAIT BENCH_LOCK FRESH

TRIAL_DIR=""
LOGS=""
CHARTS=""
LOCK_TAKEN=0
KIND_NETWORK_EXISTED=0
VALUE_SHA=""     # SHA-256 of the value the application should read
GENERATED_SHA="" # SHA-256 of the value made by the ESO Password generator
PHASE_TAG=""     # "option<TAB>run" of the install being timed, for phases.tsv
PHASE_T0=""

# Scripts run inside the OpenBao pod. The root token comes first on stdin.
# shellcheck disable=SC2016 # expanded by the pod's shell, not this one
readonly BAO_SETUP='read -r BAO_TOKEN
export BAO_TOKEN
bao secrets enable -path=secret kv-v2 >/dev/null
echo "path \"secret/data/celian/*\" { capabilities = [\"read\"] }" | bao policy write eso-read - >/dev/null
bao kv put -mount=secret celian/app password=- >/dev/null'
# shellcheck disable=SC2016
readonly BAO_ESO_TOKEN='read -r BAO_TOKEN
export BAO_TOKEN
bao token create -orphan -policy=eso-read -period=768h -field=token
bao token revoke -self >/dev/null'
# shellcheck disable=SC2016
readonly BAO_UNSEAL='read -r KEY
bao operator unseal "$KEY" >/dev/null'

# --- Helpers ------------------------------------------------------------------

log() { printf '[bench-007 %s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die() {
  log "ERROR: $*"
  exit 1
}
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
seconds_between() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", b - a }'; }
utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Elapsed time of one install step, since the start of the timed install.
phase() {
  if [ -n "$PHASE_TAG" ]; then
    tsv phases.tsv "$PHASE_TAG" "$1" "$(seconds_between "$PHASE_T0" "$(now)")"
  fi
}

tsv() {
  local file=$1
  shift
  local IFS=$'\t'
  printf '%s\n' "$*" >>"$TRIAL_DIR/$file"
}

median_range() {
  sort -n | awk '{ v[NR] = $1 } END {
    if (NR == 0) { print "-\t-"; exit }
    m = (NR % 2) ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2
    printf "%.1f\t%.1f\n", m, v[NR] - v[1] }'
}

# Short API calls; long waits and exec use kubectl directly.
kube() { kubectl --request-timeout=10s "$@"; }

# Runs "$@" until it succeeds, for at most $1 seconds.
wait_until() {
  local deadline
  deadline=$(($(date +%s) + $1))
  shift
  until "$@" >/dev/null 2>&1; do
    [ "$(date +%s)" -lt "$deadline" ] || return 1
    sleep 1
  done
}

# Random disposable value: 24 bytes from /dev/urandom, base64 without symbols.
random_value() { head -c 24 /dev/urandom | base64 | tr -d '\n/+='; }
sha_of_stdin() { shasum -a 256 | awk '{ print $1 }'; }

# Secret from a base64 value, piped from printf (a builtin: nothing on a
# command line). No heredoc: bash 3.2 writes a heredoc to a temporary file.
# kubectl create, not apply: apply copies the value into the
# last-applied-configuration annotation. create also fails if it exists.
create_secret_b64() {
  local ns=$1 name=$2 key=$3 b64=$4
  printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: %s\n  namespace: %s\ntype: Opaque\ndata:\n  %s: %s\n' \
    "$name" "$ns" "$key" "$b64" | kubectl create -f -
}

# --- Cluster ------------------------------------------------------------------

cluster_containers() {
  docker ps -a --filter "label=io.x-k8s.kind.cluster=$CLUSTER" --format '{{.Names}}'
}

# shellcheck disable=SC2016 # jq variables, not shell ones
readonly KUBE_SYSTEM_READY='
  [.items[] | select(.kind == "Pod")] as $pods
  | ($pods | length) > 0
  and all($pods[]; .status.phase == "Succeeded"
      or (.status.phase == "Running"
          and any(.status.conditions[]?; .type == "Ready" and .status == "True")))
  and all(.items[] | select(.kind == "Deployment");
      (.status.availableReplicas // 0) >= .spec.replicas)
  and all(.items[] | select(.kind == "DaemonSet");
      (.status.numberReady // 0) >= .status.desiredNumberScheduled)'

cluster_ready() {
  kube get nodes -o json | jq -e 'all(.items[]; any(.status.conditions[]?;
    .type == "Ready" and .status == "True"))' >/dev/null || return 1
  kube get pods,deployments,daemonsets -n kube-system -o json |
    jq -e "$KUBE_SYSTEM_READY" >/dev/null
}

# Every pod of the namespaces is Ready, and (if $1 > 0) started after $1.
pods_ready_since() {
  local since=$1 ns
  shift
  for ns in "$@"; do
    kube get pods -n "$ns" -o json | jq -e --argjson t "$since" '
      [.items[] | select(.status.phase != "Succeeded")] as $p
      | ($p | length) > 0
      and all($p[]; any(.status.conditions[]?; .type == "Ready" and .status == "True")
        and all(.status.containerStatuses[]?;
          (.state.running.startedAt // "1970-01-01T00:00:00Z") | fromdateiso8601 >= $t))' \
      >/dev/null || return 1
  done
}

# Prints the time of the first of READY_STREAK consecutive successes of "$@".
wait_streak() {
  local deadline streak=0 first="" t
  deadline=$(($(date +%s) + READY_TIMEOUT))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    t=$(now)
    if "$@" >/dev/null 2>&1; then
      if [ "$streak" -eq 0 ]; then first=$t; fi
      streak=$((streak + 1))
      if [ "$streak" -ge "$READY_STREAK" ]; then
        echo "$first"
        return 0
      fi
    else
      streak=0
    fi
    sleep 1
  done
  return 1
}

create_cluster() {
  kind create cluster --name "$CLUSTER" --image "$KIND_IMAGE" \
    --kubeconfig "$KUBECONFIG" >>"$LOGS/cluster.log" 2>&1 || die "kind create failed"
  wait_streak cluster_ready >/dev/null || die "cluster not ready"
  kubectl create namespace "$NS_APP" >>"$LOGS/cluster.log"
  # Pull busybox once, so that the test pod weighs on no measurement.
  run_pod_to_end warmup "true" >/dev/null || die "warm-up pod failed"
}

delete_cluster() {
  kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >>"$LOGS/cluster.log" 2>&1
}

# --- Test pods ----------------------------------------------------------------

# Runs a busybox pod with a shell command, waits for its end, prints its log.
# With $3 set, the pod reads the Secret $3 (key password) in $PASSWORD.
run_pod_to_end() {
  local name=$1 cmd=$2 secret=${3:-} env="" phase deadline
  if [ -n "$secret" ]; then
    env="      env:
        - name: PASSWORD
          valueFrom:
            secretKeyRef: {name: $secret, key: password}"
  fi
  kubectl apply -f - >>"$LOGS/pods.log" 2>&1 <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $name
  namespace: $NS_APP
spec:
  restartPolicy: Never
  securityContext: {runAsNonRoot: true, runAsUser: 65534}
  containers:
    - name: main
      image: $BUSYBOX_IMAGE
      imagePullPolicy: IfNotPresent
      command: ["sh", "-c", "$cmd"]
$env
EOF
  deadline=$(($(date +%s) + 300))
  while :; do
    phase=$(kube get pod "$name" -n "$NS_APP" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    case $phase in Succeeded | Failed) break ;; esac
    [ "$(date +%s)" -lt "$deadline" ] || break
    sleep 0.5
  done
  kubectl logs "$name" -n "$NS_APP" 2>/dev/null || true
  kubectl delete pod "$name" -n "$NS_APP" --wait=false >>"$LOGS/pods.log" 2>&1 || true
  [ "$phase" = Succeeded ]
}

# The pod prints the SHA-256 of the value it received.
# shellcheck disable=SC2016 # expanded by the pod's shell, not this one
readonly HASH_CMD='printf %s \"$PASSWORD\" | sha256sum | cut -d \" \" -f 1'

# --- OpenBao ------------------------------------------------------------------

bao_exec() {
  local ns=$1
  shift
  kubectl exec -n "$ns" openbao-0 -c openbao -- "$@"
}

# bao status exits 2 when sealed: read its JSON whatever the exit code.
bao_field() {
  { bao_exec "$1" bao status -format=json 2>/dev/null || true; } | jq -r ".$2"
}
bao_answers() { case $(bao_field "$1" initialized) in true | false) return 0 ;; esac; return 1; }
bao_unsealed() { [ "$(bao_field "$1" sealed)" = false ]; }

openbao_values() {
  local with_seal=$1
  cat <<EOF
injector:
  enabled: false
server:
  image:
    registry: "$OPENBAO_REGISTRY"
    repository: "$OPENBAO_REPOSITORY"
    tag: "$OPENBAO_TAG"
  dataStorage:
    size: 1Gi
EOF
  if [ "$with_seal" = 1 ]; then
    cat <<'EOF'
  volumes:
    - name: seal-key
      secret:
        secretName: openbao-seal-key
        defaultMode: 288
  volumeMounts:
    - name: seal-key
      mountPath: /openbao/seal
      readOnly: true
EOF
  fi
  cat <<'EOF'
  standalone:
    config: |
      ui = true
      listener "tcp" {
        tls_disable = 1
        address = "[::]:8200"
        cluster_address = "[::]:8201"
      }
      storage "pebbledb" {
        path = "/openbao/data/pebbledb"
      }
EOF
  if [ "$with_seal" = 1 ]; then
    cat <<'EOF'
      seal "static" {
        current_key_id = "celian-local-1"
        current_key = "file:///openbao/seal/key"
      }
EOF
  fi
}

helm_install_openbao() {
  local ns=$1 with_seal=$2 values="$TRIAL_DIR/openbao-values-$2.yaml"
  openbao_values "$with_seal" >"$values"
  kubectl create namespace "$ns"
  if [ "$with_seal" = 1 ]; then
    # 32 random bytes for AES-256-GCM-96, generated here, never on disk.
    create_secret_b64 "$ns" openbao-seal-key key "$(head -c 32 /dev/urandom | base64 | tr -d '\n')"
  fi
  helm install openbao "$CHARTS/$OPENBAO_CHART_FILE" -n "$ns" -f "$values"
  phase openbao-helm
  wait_until 600 bao_answers "$ns" || die "OpenBao in $ns does not answer"
  phase openbao-answers
}

# Initialises OpenBao with the static seal, writes the test value, creates a
# read-only token for ESO, revokes the root token.
setup_openbao() {
  local root value eso_token
  helm_install_openbao "$NS_BAO" 1
  root=$(bao_exec "$NS_BAO" bao operator init -format=json -recovery-shares=1 \
    -recovery-threshold=1 | jq -r '.root_token')
  case $root in "" | null) die "bao operator init returned no root token" ;; esac
  wait_until 120 bao_unsealed "$NS_BAO" || die "OpenBao still sealed after init"
  phase openbao-unsealed
  value=$(random_value)
  VALUE_SHA=$(printf '%s' "$value" | sha_of_stdin)
  { printf '%s\n' "$root"; printf '%s' "$value"; } |
    kubectl exec -i -n "$NS_BAO" openbao-0 -c openbao -- sh -ec "$BAO_SETUP"
  value=""
  eso_token=$(printf '%s\n' "$root" |
    kubectl exec -i -n "$NS_BAO" openbao-0 -c openbao -- sh -ec "$BAO_ESO_TOKEN")
  root=""
  [ -n "$eso_token" ] || die "no token for ESO"
  create_secret_b64 "$NS_APP" openbao-eso-token token "$(printf '%s' "$eso_token" | base64 | tr -d '\n')"
  eso_token=""
  phase openbao-configured
}

# --- ESO ----------------------------------------------------------------------

install_eso() {
  kubectl create namespace "$NS_ESO"
  helm install eso "$CHARTS/$ESO_CHART_FILE" -n "$NS_ESO" \
    --set "image.tag=$ESO_TAG" --set "webhook.image.tag=$ESO_TAG" \
    --set "certController.image.tag=$ESO_TAG"
  phase eso-helm
  kubectl wait --for=condition=Available deployment --all -n "$NS_ESO" --timeout=600s
  phase eso-available
}

eso_store_manifest() {
  case $1 in
    openbao)
      cat <<EOF
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata: {name: openbao, namespace: $NS_APP}
spec:
  provider:
    vault:
      server: "$BAO_URL"
      path: secret
      version: v2
      auth:
        tokenSecretRef: {name: openbao-eso-token, key: token}
EOF
      ;;
    eso)
      cat <<EOF
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata: {name: k8s-src, namespace: $NS_APP}
spec:
  provider:
    kubernetes:
      remoteNamespace: $NS_SRC
      server:
        caProvider: {type: ConfigMap, name: kube-root-ca.crt, key: ca.crt}
      auth:
        serviceAccount: {name: eso-reader}
EOF
      ;;
  esac
}

store_name() { case $1 in openbao) echo openbao ;; eso) echo k8s-src ;; esac; }
remote_key() { case $1 in openbao) echo celian/app ;; eso) echo app-source ;; esac; }

store_ready() {
  [ "$(kube get secretstore "$1" -n "$NS_APP" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" = True ]
}

apply_store() { eso_store_manifest "$1" | kube apply -f -; }

# Read access for ESO to the source namespace, as in the ESO documentation.
source_rbac() {
  cat <<EOF
apiVersion: v1
kind: ServiceAccount
metadata: {name: eso-reader, namespace: $NS_APP}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: eso-reader, namespace: $NS_SRC}
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["authorization.k8s.io"]
    resources: ["selfsubjectrulesreviews"]
    verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: eso-reader, namespace: $NS_SRC}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: Role, name: eso-reader}
subjects:
  - {kind: ServiceAccount, name: eso-reader, namespace: $NS_APP}
EOF
}

external_secret_manifest() {
  cat <<EOF
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata: {name: app-db, namespace: $NS_APP}
spec:
  refreshInterval: 1h
  secretStoreRef: {name: $(store_name "$1"), kind: SecretStore}
  target: {name: app-db}
  data:
    - secretKey: password
      remoteRef: {key: $(remote_key "$1"), property: password}
EOF
}

# --- Options ------------------------------------------------------------------

option_namespaces() {
  case $1 in
    openbao) echo "$NS_BAO $NS_ESO" ;;
    eso) echo "$NS_ESO" ;;
    native) echo "" ;;
  esac
}

install_option() {
  local opt=$1 value
  case $opt in
    openbao)
      setup_openbao
      install_eso
      ;;
    eso)
      kubectl create namespace "$NS_SRC"
      value=$(random_value)
      VALUE_SHA=$(printf '%s' "$value" | sha_of_stdin)
      create_secret_b64 "$NS_SRC" app-source password "$(printf '%s' "$value" | base64 | tr -d '\n')"
      value=""
      install_eso
      source_rbac | kubectl apply -f -
      ;;
    native)
      value=$(random_value)
      VALUE_SHA=$(printf '%s' "$value" | sha_of_stdin)
      create_secret_b64 "$NS_APP" app-db password "$(printf '%s' "$value" | base64 | tr -d '\n')"
      value=""
      return 0
      ;;
  esac
  # The ESO webhook may refuse objects for a moment after its rollout.
  wait_until 180 apply_store "$opt" || die "$opt: SecretStore not accepted"
  phase store-accepted
  wait_until 180 store_ready "$(store_name "$opt")" || die "$opt: SecretStore not Ready"
  phase store-ready
}

option_ready() {
  local opt=$1 since=$2
  case $opt in
    openbao)
      pods_ready_since "$since" "$NS_BAO" "$NS_ESO" && bao_unsealed "$NS_BAO" &&
        externalsecret_ready app-db
      ;;
    eso) pods_ready_since "$since" "$NS_ESO" && externalsecret_ready app-db ;;
    native) kube get secret app-db -n "$NS_APP" ;;
  esac
}

externalsecret_ready() {
  [ "$(kube get externalsecret "$1" -n "$NS_APP" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" = True ]
}

uninstall_option() {
  local opt=$1
  kubectl delete pod --all -n "$NS_APP" --ignore-not-found >>"$LOGS/uninstall.log" 2>&1
  if kube get crd externalsecrets.external-secrets.io >/dev/null 2>&1; then
    kubectl delete externalsecrets,secretstores --all -n "$NS_APP" >>"$LOGS/uninstall.log" 2>&1
    kubectl delete passwords.generators.external-secrets.io --all -n "$NS_APP" \
      >>"$LOGS/uninstall.log" 2>&1 || true
  fi
  if helm status eso -n "$NS_ESO" >/dev/null 2>&1; then
    helm uninstall eso -n "$NS_ESO" >>"$LOGS/uninstall.log" 2>&1
  fi
  if helm status openbao -n "$NS_BAO" >/dev/null 2>&1; then
    helm uninstall openbao -n "$NS_BAO" >>"$LOGS/uninstall.log" 2>&1
  fi
  kubectl delete namespace "$NS_APP" "$NS_BAO" "$NS_ESO" "$NS_SRC" --ignore-not-found \
    --timeout=300s >>"$LOGS/uninstall.log" 2>&1 || die "$opt: namespaces not deleted"
  wait_until 300 nothing_left || die "$opt: CRDs or volumes left after uninstall"
  kubectl create namespace "$NS_APP" >>"$LOGS/uninstall.log"
}

nothing_left() {
  [ -z "$(kube get crd -o name | grep 'external-secrets.io' || true)" ] &&
    [ -z "$(kube get pv -o name)" ]
}

# --- Records ------------------------------------------------------------------

# Load average, and the other kind clusters of this project by name; other
# containers by count only, their names belong to other projects.
record_load() {
  local opt=$1 phase=$2 loadavg others total mine
  loadavg=$(uptime | sed -e 's/.*load average[s]*: //' -e 's/,//g')
  others=$(docker ps --filter label=io.x-k8s.kind.cluster \
    --format '{{.Label "io.x-k8s.kind.cluster"}}' | sort -u |
    grep '^celian-bench-' | grep -vx "$CLUSTER" | paste -sd, - || true)
  total=$(docker ps -q | wc -l | tr -d ' ')
  mine=$(docker ps -q --filter "label=io.x-k8s.kind.cluster=$CLUSTER" | wc -l | tr -d ' ')
  tsv load.tsv "$(utc_now)" "$opt" "$phase" "$loadavg" "${others:--}" "$((total - mine))"
}

# One kubelet summary sample. Prints, for the option's pods then for the
# kube-system pods (API server, etcd and the rest of the control plane):
# "cpu_pct<TAB>mem_mib<TAB>pods<TAB>ks_cpu_pct<TAB>ks_mem_mib".
# shellcheck disable=SC2016 # jq variables, not shell ones
readonly JQ_SUMS='
  def cpu: (map(.cpu.usageNanoCores // 0) | add // 0) / 1e7 * 100 | round / 100;
  def mem: (map(.memory.workingSetBytes // 0) | add // 0) / 1048576 * 10 | round / 10;
  ($nss | split(" ") | map(select(. != ""))) as $n'

idle_sample() {
  local opt=$1 run=$2 sample=$3 nss summary
  nss=$(option_namespaces "$opt")
  summary=$(kube get --raw "/api/v1/nodes/$NODE/proxy/stats/summary")
  printf '%s' "$summary" | jq -r --arg nss "$nss kube-system" --arg o "$opt" --arg r "$run" --arg s "$sample" "$JQ_SUMS"'
    | .pods[] | select(.podRef.namespace as $x | any($n[]; . == $x))
    | [$o, $r, $s, .podRef.namespace + "/" + .podRef.name,
       ([.] | cpu), ([.] | mem)] | @tsv' >>"$TRIAL_DIR/idle-samples.tsv"
  printf '%s' "$summary" | jq -r --arg nss "$nss" "$JQ_SUMS"'
    | [.pods[] | select(.podRef.namespace as $x | any($n[]; . == $x))] as $p
    | [.pods[] | select(.podRef.namespace == "kube-system")] as $k
    | "\($p | cpu)\t\($p | mem)\t\($p | length)\t\($k | cpu)\t\($k | mem)"'
}

node_mem_mib() {
  docker stats --no-stream --format '{{.MemUsage}}' "$NODE" | awk '{
    v = $1; n = v; sub(/[A-Za-z]+$/, "", n); u = v; sub(/^[0-9.]+/, "", u)
    if (u == "GiB") n *= 1024; else if (u == "KiB") n /= 1024
    printf "%.1f\n", n }'
}

# Pulled events of the option's namespaces: pulled from the registry, or
# already present in the node.
record_node_images() {
  local opt=$1 phase=$2 ns status image
  for ns in $(option_namespaces "$opt"); do
    kube get events -n "$ns" -o json | jq -r '.items[] | select(.reason == "Pulled") | .message' |
      sed -n -e 's/^Successfully pulled image "\([^"]*\)".*/pulled|\1/p' \
        -e 's/^Container image "\([^"]*\)" already present.*/present|\1/p' |
      sort -u | while IFS='|' read -r status image; do
        tsv node-images.tsv "$opt" "$phase" "$status" "$image"
      done
  done
}

count_pulls() {
  awk -F'\t' -v o="$1" -v p="$2" '$1 == o && $2 == p { if ($3 == "pulled") d++; else a++ }
    END { printf "%d\t%d\n", d, a }' "$TRIAL_DIR/node-images.tsv"
}

# Compressed size per architecture, read from the registry manifest.
registry_sizes() {
  local sizes
  sizes=$(docker manifest inspect -v "$1" 2>/dev/null | jq -r '
    [if type == "array" then .[] else . end
     | select(.Descriptor.platform.os == "linux")
     | (.SchemaV2Manifest // .OCIManifest) as $m
     | "\(.Descriptor.platform.architecture)=\(([$m.layers[]?.size] | add) + ($m.config.size // 0))"]
    | map(select(startswith("arm64=") or startswith("amd64="))) | join(",")' 2>/dev/null || true)
  echo "${sizes:--}"
}

record_images() {
  local ref
  for ref in "$OPENBAO_REGISTRY/$OPENBAO_REPOSITORY@${OPENBAO_TAG#*@}" \
    "$ESO_REPOSITORY@${ESO_TAG#*@}" "${BUSYBOX_IMAGE%%:*}@${BUSYBOX_IMAGE#*@}"; do
    tsv images.tsv "$ref" "$(registry_sizes "$ref")"
  done
}

# --- One run ------------------------------------------------------------------

# Injection: an ExternalSecret (except native) and a pod that reads the value.
inject() {
  local opt=$1 tag=$2 t0 got
  t0=$(now)
  if [ "$opt" != native ] && ! kube get externalsecret app-db -n "$NS_APP" >/dev/null 2>&1; then
    external_secret_manifest "$opt" | kubectl apply -f - >>"$LOGS/pods.log" 2>&1
  fi
  got=$(run_pod_to_end "inject-$tag" "$HASH_CMD" app-db || true)
  printf '%s\t%s\n' "$(seconds_between "$t0" "$(now)")" \
    "$(if [ -n "$got" ] && [ "$got" = "$VALUE_SHA" ]; then echo yes; else echo no; fi)"
}

timed_run() {
  local opt=$1 run=$2 state=$3 log_file t0 t_ready injection wake samples="" i s
  local cpu mem pods ks_cpu ks_mem node_mem started
  log_file="$LOGS/$opt-run-$run.log"
  record_load "$opt" "run-$run"
  log "$opt run $run ($state): install, output in $log_file"
  started=$(utc_now)
  t0=$(now)
  PHASE_TAG="$opt"$'\t'"$run"
  PHASE_T0=$t0
  # Called without || so that set -e stays active inside install_option.
  install_option "$opt" >"$log_file" 2>&1
  t_ready=$(now)
  PHASE_TAG=""
  log "$opt run $run: ready in $(seconds_between "$t0" "$t_ready") s"
  injection=$(inject "$opt" "run-$run")
  log "$opt run $run: injection $injection"
  wake=$(awk -v t="$t_ready" -v w="$IDLE_WAIT" -v n="$(now)" 'BEGIN { d = t + w - n; printf "%.1f", (d > 0 ? d : 0) }')
  sleep "$wake"
  for i in $(seq 1 "$SAMPLES"); do
    s=$(idle_sample "$opt" "$run" "$i")
    samples="$samples$s"$'\n'
    if [ "$i" -lt "$SAMPLES" ]; then sleep "$SAMPLE_GAP"; fi
  done
  cpu=$(printf '%s' "$samples" | cut -f1 | grep . | median_range | cut -f1)
  mem=$(printf '%s' "$samples" | cut -f2 | grep . | median_range | cut -f1)
  pods=$(printf '%s' "$samples" | head -1 | cut -f3)
  ks_cpu=$(printf '%s' "$samples" | cut -f4 | grep . | median_range | cut -f1)
  ks_mem=$(printf '%s' "$samples" | cut -f5 | grep . | median_range | cut -f1)
  node_mem=$(node_mem_mib)
  record_node_images "$opt" "run-$run"
  tsv runs.tsv "$opt" "$run" "$state" "$(seconds_between "$t0" "$t_ready")" "$injection" \
    "$mem" "$cpu" "$pods" "$node_mem" "$(count_pulls "$opt" "run-$run")" "$ks_mem" "$ks_cpu" "$started"
}

# --- Restart ------------------------------------------------------------------

api_port() { docker port "$NODE" 6443/tcp | head -1; }

restart_once() {
  local opt=$1 i=$2 port_before port_after t0 t_node t_opt since sealed="-" kept gen="-"
  record_load "$opt" "restart-$i"
  port_before=$(api_port)
  docker stop "$NODE" >>"$LOGS/restart.log"
  since=$(date +%s)
  t0=$(now)
  docker start "$NODE" >>"$LOGS/restart.log"
  kind export kubeconfig --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >>"$LOGS/restart.log" 2>&1
  port_after=$(api_port)
  t_node=$(wait_streak cluster_ready) || die "$opt: cluster not ready after restart $i"
  t_opt=$(wait_streak option_ready "$opt" "$((since - 2))") || die "$opt: not ready after restart $i"
  if [ "$opt" = openbao ]; then sealed=$(bao_field "$NS_BAO" sealed); fi
  kept=$(inject "$opt" "restart-$i" | cut -f2)
  if [ -n "$GENERATED_SHA" ]; then
    gen=$(if [ "$(generated_sha)" = "$GENERATED_SHA" ]; then echo yes; else echo no; fi)
  fi
  log "$opt restart $i: node $(seconds_between "$t0" "$t_node") s, option $(seconds_between "$t0" "$t_opt") s, sealed $sealed, value kept $kept"
  tsv restarts.tsv "$opt" "$i" "$(seconds_between "$t0" "$t_node")" \
    "$(seconds_between "$t0" "$t_opt")" "$sealed" "$kept" "$gen" "$port_before" "$port_after"
}

generated_sha() {
  kube get secret app-gen -n "$NS_APP" -o jsonpath='{.data.password}' | base64 -d | sha_of_stdin
}

# --- Functional checks --------------------------------------------------------

check() {
  log "$1 $2: $3 ($4)"
  tsv functional.tsv "$@"
}

# Services, host ports, access without a token, etcd encryption flag.
check_exposure() {
  local opt=$1 ns out flags
  for ns in $(option_namespaces "$opt"); do
    kube get svc -n "$ns" -o json | jq -r --arg o "$opt" '.items[] |
      [$o, "service", .metadata.namespace + "/" + .metadata.name, .spec.type,
       ([.spec.ports[] | "\(.port)/\(.protocol)"] | join(","))] | @tsv' >>"$TRIAL_DIR/ports.tsv"
    kube get pods -n "$ns" -o json | jq -r --arg o "$opt" '.items[] |
      [$o, "pod", .metadata.namespace + "/" + .metadata.name,
       "hostNetwork=\(.spec.hostNetwork // false)",
       "hostPorts=\([.spec.containers[].ports[]?.hostPort // empty] | join(","))"] | @tsv' \
      >>"$TRIAL_DIR/ports.tsv"
  done
  tsv ports.tsv "$opt" node-container "$NODE" "$(docker port "$NODE" | paste -sd, -)" \
    "$(lsof -nP -iTCP:"$(api_port | sed 's/.*://')" -sTCP:LISTEN 2>/dev/null |
      awk 'NR > 1 { print $1 "=" $9 }' | sort -u | paste -sd, -)"
  flags=$(kube get pods -n kube-system -l component=kube-apiserver -o json |
    jq '[.items[0].spec.containers[0].command[] | select(startswith("--encryption-provider-config"))] | length')
  check "$opt" etcd-encryption "$(if [ "$flags" -gt 0 ]; then echo yes; else echo no; fi)" \
    "--encryption-provider-config flags on kube-apiserver: $flags"
  if [ "$opt" = openbao ]; then
    out=$(run_pod_to_end probe "wget -q -O - -T 5 $BAO_URL/v1/sys/health; echo; wget -S -O /dev/null -T 5 $BAO_URL/v1/secret/data/celian/app 2>&1 | grep -m 1 HTTP/" || true)
    check openbao no-token-health "$(printf '%s' "$out" | grep -q '"sealed":false' && echo reachable || echo unreachable)" \
      "GET /v1/sys/health from $NS_APP, no token: $(printf '%s' "$out" | head -1 | cut -c 1-120)"
    check openbao no-token-secret "$(printf '%s' "$out" | grep -q ' 403' && echo denied || echo other)" \
      "GET /v1/secret/data/celian/app from $NS_APP, no token: $(printf '%s' "$out" | tail -1 | tr -s ' ')"
    check openbao listener yes "$(kube get configmap openbao-config -n "$NS_BAO" -o json |
      jq -r '.data[]' | grep -E 'address|tls_disable' | tr -s ' ' | paste -sd ';' -)"
  fi
}

# ESO Password generator, CreatedOnce: a random value without any input.
check_generator() {
  kubectl apply -f - >>"$LOGS/eso-functional.log" 2>&1 <<EOF
apiVersion: generators.external-secrets.io/v1alpha1
kind: Password
metadata: {name: app-gen, namespace: $NS_APP}
spec: {length: 32, digits: 5, symbols: 0, noUpper: false, allowRepeat: true}
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata: {name: app-gen, namespace: $NS_APP}
spec:
  refreshPolicy: CreatedOnce
  target: {name: app-gen}
  dataFrom:
    - sourceRef:
        generatorRef: {apiVersion: generators.external-secrets.io/v1alpha1, kind: Password, name: app-gen}
EOF
  if wait_until 120 externalsecret_ready app-gen; then
    GENERATED_SHA=$(generated_sha)
    check eso password-generator yes "Secret app-gen created, $(kube get secret app-gen -n "$NS_APP" \
      -o jsonpath='{.data.password}' | base64 -d | wc -c | tr -d ' ') characters, refreshPolicy CreatedOnce"
  else
    check eso password-generator no "ExternalSecret app-gen not Ready, see logs/eso-functional.log"
  fi
}

# OpenBao with the default Shamir seal: sealed again after a restart?
check_shamir() {
  local log_file="$LOGS/openbao-shamir.log" init key t0 since t_unsealed sealed
  helm_install_openbao "$NS_SHAMIR" 0 >"$log_file" 2>&1
  init=$(bao_exec "$NS_SHAMIR" bao operator init -format=json -key-shares=1 -key-threshold=1)
  key=$(printf '%s' "$init" | jq -r '.unseal_keys_b64[0]')
  init=""
  printf '%s\n' "$key" | kubectl exec -i -n "$NS_SHAMIR" openbao-0 -c openbao -- sh -ec "$BAO_UNSEAL"
  wait_until 60 bao_unsealed "$NS_SHAMIR" || die "Shamir variant not unsealed"
  docker stop "$NODE" >>"$log_file"
  since=$(date +%s)
  docker start "$NODE" >>"$log_file"
  kind export kubeconfig --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >>"$log_file" 2>&1
  wait_streak cluster_ready >/dev/null || die "cluster not ready after the Shamir restart"
  wait_until 300 shamir_restarted "$((since - 2))" || die "Shamir pod did not restart"
  sealed=$(bao_field "$NS_SHAMIR" sealed)
  check openbao shamir-sealed-after-restart "$sealed" "Shamir seal, 1 share; bao status after docker stop/start"
  t0=$(now)
  printf '%s\n' "$key" | kubectl exec -i -n "$NS_SHAMIR" openbao-0 -c openbao -- sh -ec "$BAO_UNSEAL"
  key=""
  if wait_until 60 bao_unsealed "$NS_SHAMIR"; then
    t_unsealed=$(now)
    check openbao shamir-manual-unseal yes "unsealed $(seconds_between "$t0" "$t_unsealed") s after the key was sent"
  else
    check openbao shamir-manual-unseal no "still sealed 60 s after the key was sent"
  fi
  helm uninstall openbao -n "$NS_SHAMIR" >>"$log_file" 2>&1
  kubectl delete namespace "$NS_SHAMIR" --timeout=300s >>"$log_file" 2>&1
}

shamir_restarted() {
  kube get pod openbao-0 -n "$NS_SHAMIR" -o json | jq -e --argjson t "$1" '
    all(.status.containerStatuses[]; (.state.running.startedAt // "1970-01-01T00:00:00Z")
      | fromdateiso8601 >= $t)' >/dev/null && bao_answers "$NS_SHAMIR"
}

# --- Series -------------------------------------------------------------------

# FRESH=1: RUNS installs, each on a new cluster, as task up does on a new
# node. Install, injection and idle samples only (no restart, no checks).
series_fresh() {
  local opt=$1 run=1
  while [ "$run" -le "$RUNS" ]; do
    record_load "$opt" "fresh-$run"
    log "$opt: fresh cluster for run $run"
    create_cluster
    timed_run "$opt" "$run" fresh
    delete_cluster
    [ -z "$(cluster_containers)" ] || die "cluster containers left after delete"
    if [ "$run" -lt "$RUNS" ]; then sleep "$PAUSE_BETWEEN_RUNS"; fi
    run=$((run + 1))
  done
}

series() {
  local opt=$1 run i
  if [ "$FRESH" = 1 ]; then
    series_fresh "$opt"
    return 0
  fi
  record_load "$opt" series-start
  log "$opt: fresh cluster"
  create_cluster
  timed_run "$opt" 0 cold
  uninstall_option "$opt"
  run=1
  while [ "$run" -le "$RUNS" ]; do
    sleep "$PAUSE_BETWEEN_RUNS"
    timed_run "$opt" "$run" warm
    if [ "$run" -lt "$RUNS" ] || [ "$RESTARTS" = 0 ]; then uninstall_option "$opt"; fi
    run=$((run + 1))
  done
  if [ "$RESTARTS" != 0 ]; then
    if [ "$RUNS" = 0 ]; then install_option "$opt" >>"$LOGS/$opt-restart.log" 2>&1; fi
    if [ "$FUNCTIONAL" = 1 ]; then
      check_exposure "$opt"
      if [ "$opt" = eso ]; then check_generator; fi
    fi
    i=1
    while [ "$i" -le "$RESTARTS" ]; do
      restart_once "$opt" "$i"
      i=$((i + 1))
    done
    GENERATED_SHA=""
    uninstall_option "$opt"
  fi
  if [ "$FUNCTIONAL" = 1 ] && [ "$opt" = openbao ]; then check_shamir; fi
  delete_cluster
  [ -z "$(cluster_containers)" ] || die "cluster containers left after delete"
}

# --- Start-up checks ----------------------------------------------------------

check_versions() {
  local v
  for v in docker kind kubectl helm gh jq perl shasum lsof base64; do
    command -v "$v" >/dev/null || die "$v not found"
  done
  v=$(kind version | awk '{ print $2 }')
  [ "$v" = "$KIND_VERSION" ] || die "kind $v found, $KIND_VERSION expected"
  tsv versions.tsv kind "$v"
  v=$(kubectl version --client -o json | jq -r '.clientVersion.minor' | tr -dc '0-9')
  case " $KUBECTL_MINORS " in
    *" $v "*) ;;
    *) die "kubectl 1.$v is more than one minor away from $K8S_VERSION" ;;
  esac
  tsv versions.tsv kubectl "$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion')"
  v=$(helm version --short)
  case $v in "$HELM_MAJOR".*) ;; *) die "helm $v found, $HELM_MAJOR expected" ;; esac
  tsv versions.tsv helm "$v"
  tsv versions.tsv docker "$(docker version --format '{{.Server.Version}}')"
  tsv versions.tsv engine "$(docker info --format '{{.OperatingSystem}} {{.NCPU}} CPU {{.MemTotal}} B cgroup v{{.CgroupVersion}}')"
  tsv versions.tsv host "$(sysctl -n hw.model 2>/dev/null || uname -m) $(sw_vers -productVersion 2>/dev/null || uname -r)"
}

# Downloads a chart with gh and checks its SHA-256 and its appVersion.
fetch_chart() {
  local repo=$1 tag=$2 file=$3 sha=$4 app=$5 sum
  gh release download "$tag" -R "$repo" -p "$file" -D "$CHARTS" >>"$LOGS/charts.log" 2>&1 ||
    die "gh release download $tag failed"
  sum=$(shasum -a 256 "$CHARTS/$file" | awk '{ print $1 }')
  [ "$sum" = "$sha" ] || die "$file: SHA-256 $sum differs from $sha"
  [ "$(helm show chart "$CHARTS/$file" | awk '/^appVersion:/ { print $2 }')" = "$app" ] ||
    die "$file: appVersion differs from $app"
  tsv versions.tsv "$file" "$sha"
}

check_no_cluster() {
  [ -z "$(cluster_containers)" ] || die "a kind cluster named $CLUSTER already exists"
  [ -z "$(docker ps -aq --filter "name=^/?$CLUSTER")" ] || die "a container named $CLUSTER* already exists"
}

take_lock() {
  [ -n "$BENCH_LOCK" ] || return 0
  if ! mkdir "$BENCH_LOCK" 2>/dev/null; then
    echo "lock held: $BENCH_LOCK ($(cat "$BENCH_LOCK/owner" 2>/dev/null || echo 'no owner file'))" >&2
    exit 3
  fi
  LOCK_TAKEN=1
  printf 'BENCH-007 %s\n' "$(utc_now)" >"$BENCH_LOCK/owner"
}

release_lock() {
  if [ "$LOCK_TAKEN" = 1 ]; then
    rm -f "$BENCH_LOCK/owner"
    rmdir "$BENCH_LOCK" && log "lock released"
    LOCK_TAKEN=0
  fi
}

# --- Cleanup and summary ------------------------------------------------------

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  set +e
  if [ -n "$(cluster_containers)" ]; then
    log "cleanup: deleting the kind cluster $CLUSTER"
    delete_cluster
  fi
  if [ "$KIND_NETWORK_EXISTED" = 0 ] && docker network inspect kind >/dev/null 2>&1 &&
    [ "$(docker network inspect kind --format '{{len .Containers}}')" = 0 ]; then
    log "cleanup: removing the kind network created by this run"
    docker network rm kind >>"$LOGS/cleanup.log" 2>&1
  fi
  release_lock
  log "results in $TRIAL_DIR"
  exit "$rc"
}

summarize() {
  local opt column name values
  tsv summary.tsv option metric runs values median range
  for opt in $OPTIONS; do
    for column in 4:install_s 5:inject_s 7:mem_mib 8:cpu_pct 13:ks_mem_mib 14:ks_cpu_pct; do
      name=${column#*:}
      values=$(awk -F'\t' -v o="$opt" -v c="${column%%:*}" \
        '$1 == o && ($3 == "warm" || $3 == "fresh") { print $c }' "$TRIAL_DIR/runs.tsv")
      tsv summary.tsv "$opt" "$name" "$(printf '%s\n' "$values" | grep -c .)" \
        "$(printf '%s\n' "$values" | paste -sd, -)" "$(printf '%s\n' "$values" | median_range)"
    done
    for column in 3:restart_node_s 4:restart_option_s; do
      name=${column#*:}
      values=$(awk -F'\t' -v o="$opt" -v c="${column%%:*}" '$1 == o { print $c }' "$TRIAL_DIR/restarts.tsv")
      tsv summary.tsv "$opt" "$name" "$(printf '%s\n' "$values" | grep -c .)" \
        "$(printf '%s\n' "$values" | paste -sd, -)" "$(printf '%s\n' "$values" | median_range)"
    done
  done
}

# --- Main -----------------------------------------------------------------------

main() {
  local opt
  if [ $# -gt 0 ]; then
    TRIAL_DIR=$1
    if [ -e "$TRIAL_DIR" ] && [ -n "$(ls -A "$TRIAL_DIR")" ]; then
      echo "TRIAL_DIR must be missing or empty: $TRIAL_DIR" >&2
      exit 2
    fi
    mkdir -p "$TRIAL_DIR"
  else
    TRIAL_DIR=$(mktemp -d)
  fi
  TRIAL_DIR=$(CDPATH='' cd -- "$TRIAL_DIR" && pwd)
  LOGS="$TRIAL_DIR/logs"
  CHARTS="$TRIAL_DIR/charts"
  mkdir -p "$LOGS" "$CHARTS"
  export KUBECONFIG="$TRIAL_DIR/kubeconfig"
  export HELM_CONFIG_HOME="$TRIAL_DIR/helm/config"
  export HELM_CACHE_HOME="$TRIAL_DIR/helm/cache"
  export HELM_DATA_HOME="$TRIAL_DIR/helm/data"
  : >"$KUBECONFIG"
  chmod 600 "$KUBECONFIG"

  tsv runs.tsv option run kind install_s inject_s inject_match mem_mib cpu_pct pods \
    node_mem_mib pulled_downloaded pulled_present ks_mem_mib ks_cpu_pct started_utc
  tsv idle-samples.tsv option run sample pod cpu_pct mem_mib
  tsv restarts.tsv option restart node_ready_s option_ready_s sealed value_kept \
    generated_kept api_port_before api_port_after
  tsv ports.tsv option kind name detail host_listeners
  tsv images.tsv image compressed_bytes
  tsv node-images.tsv option phase status image
  tsv phases.tsv option run step elapsed_s
  tsv functional.tsv option check result detail
  tsv load.tsv utc option phase loadavg_1_5_15 other_celian_clusters other_containers
  tsv versions.tsv item version

  # Start-up checks first, without any trap: a refusal deletes nothing.
  for opt in $OPTIONS; do
    case $opt in openbao | eso | native) ;; *) die "unknown option: $opt" ;; esac
  done
  check_versions
  check_no_cluster
  fetch_chart "$OPENBAO_CHART_REPO" "$OPENBAO_CHART_TAG" "$OPENBAO_CHART_FILE" \
    "$OPENBAO_CHART_SHA256" "$OPENBAO_APP_VERSION"
  fetch_chart "$ESO_CHART_REPO" "$ESO_CHART_TAG" "$ESO_CHART_FILE" "$ESO_CHART_SHA256" "$ESO_APP_VERSION"
  if docker network inspect kind >/dev/null 2>&1; then KIND_NETWORK_EXISTED=1; fi
  take_lock
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  log "trial directory: $TRIAL_DIR"
  record_images

  for opt in $OPTIONS; do
    series "$opt"
    sleep "$PAUSE_BETWEEN_RUNS"
  done
  summarize
  column -t -s "$(printf '\t')" "$TRIAL_DIR/summary.tsv" >&2 || true
}

main "$@"
