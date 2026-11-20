#!/usr/bin/env bash
# BENCH-004: Gateway API controller for the generated project, on a kind
# cluster (ADR-004). Options: Envoy Gateway, Cilium, Traefik, plus a baseline
# kind cluster without any gateway. Every run creates a fresh cluster, so the
# platform (cluster plus gateway) is measured as a whole: Cilium replaces the
# kind CNI and kube-proxy, and its share cannot be split from the cluster's.
#
# For each run the script measures:
#   - the time from `kind create cluster` to the first HTTP answer of a test
#     backend through the gateway, on 127.0.0.1 (kind extraPortMappings with
#     listenAddress 127.0.0.1), then the first HTTPS answer (TLS terminated by
#     the gateway with a Kubernetes Secret);
#   - CPU and memory of the cluster containers at rest, IDLE_WAIT seconds
#     after the first answer (`docker stats --no-stream`, 3 samples 10 s
#     apart), and per pod from the kubelet stats summary API;
#   - the images the node pulled from a registry or found already present.
# The Gateway and HTTPRoute manifest is the same for every option, except for
# gatewayClassName. Run 0 is cold: the node pulls the gateway images from
# their registries. Runs 1 to RUNS are warm, as in BENCH-003: the images are
# in the Docker cache of the host (pulled by tag before the timer, digest
# checked) and loaded into the node with `kind load docker-image`, timed, as
# `task up` would preload them. The baseline has no gateway: RUNS runs only.
#
# Usage: tests/bench/bench-004-gateway.sh [TRIAL_DIR]
#   TRIAL_DIR, if given, must be missing or empty (default: a new mktemp -d).
#   Environment:
#     OPTIONS="baseline envoy-gateway cilium traefik"  measured in this order
#     RUNS=3         runs per option after run 0 (baseline: RUNS runs only)
#     PRELOAD=1      warm runs preload the images with kind load; 0: they
#                    let the node pull them, like the cold run
#     IDLE_WAIT=120  seconds between the first answer and the first sample
#     BENCH_LOCK_DIR directory used as a lock shared by the benchmarks that
#                    use the same container engine; unset: no lock
#   Results (TSV) in TRIAL_DIR: versions.tsv, load.tsv, runs.tsv,
#   idle-samples.tsv, pods.tsv, ports.tsv, images.tsv, node-images.tsv,
#   functional.tsv, leftovers.tsv, summary.tsv; command output in logs/.
# Needs: bash >= 3.2, docker, kind, kubectl (1.35 to 1.37), helm, gh, jq,
#   perl, nc, lsof, openssl, shasum.
#
# Safety:
#   - every cluster is named celian-bench-004. The script refuses to start if
#     a container of that cluster exists or if a port it publishes is in use.
#     The checks run again once the lock is taken. Its EXIT trap is set only
#     after that, so a refusal deletes nothing and releases the lock;
#     afterwards it deletes only that cluster;
#   - umask 077; KUBECONFIG and the Helm directories live in TRIAL_DIR, so
#     ~/.kube and ~/.config/helm are neither read nor written;
#   - charts, CRD bundle and images are pinned: charts and CRDs by SHA-256,
#     checked before use, images by digest;
#   - the lock: mkdir BENCH_LOCK_DIR, with an "owner" file refreshed at every
#     run. A lock whose owner file is older than 90 minutes is stale: it is
#     removed and the removal logged. The lock is released by the EXIT trap.
# Side effects outside TRIAL_DIR: the Docker image cache (warm runs pull the
# gateway images by tag, digest checked, and they stay cached) and
# the "kind" Docker network, removed at the end if this run created it and
# nothing uses it. Ports 18080 and 18443 are published on 127.0.0.1 only.
#
# One file above the usual 800-line ceiling, on purpose: the script is run on
# its own, by hand or by a reviewer, and must stay readable and copyable
# without a library next to it.
set -euo pipefail
umask 077

# --- Pinned versions ----------------------------------------------------------

readonly KIND_VERSION="v0.33.0"
readonly KUBECTL_MINORS="35 36 37"
# Same node image as BENCH-003 (kind v0.33.0 release notes: digest required).
readonly KIND_IMAGE="kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed"

readonly GATEWAY_API_VERSION="v1.7.0"
readonly GATEWAY_API_REPO="kubernetes-sigs/gateway-api"
readonly GATEWAY_API_FILE="standard-install.yaml"
readonly GATEWAY_CRDS_SHA256="4e2602c4cbe1afbc394d86f4ac6522e1a5263b01133bba1e40a6d1a549e753a1"

# Charts, SHA-256 of the .tgz read on 2026-11-19.
readonly EG_CHART="oci://docker.io/envoyproxy/gateway-helm"
readonly EG_CRDS_CHART="oci://docker.io/envoyproxy/gateway-crds-helm"
readonly EG_VERSION="v1.10.0"
readonly EG_CHART_SHA256="0f72c9050c33dbaab39b865e8cb5ed77f263720b22368eda4ce687077649e659"
readonly EG_CRDS_CHART_SHA256="cc213d9059d0391d69d70bef7c041fb1c1e45270c84a65988229bd88639d0aa5"
readonly CILIUM_REPO="https://helm.cilium.io"
readonly CILIUM_VERSION="1.20.5"
readonly CILIUM_CHART_SHA256="0c7592eb75179ecf46dd3ec22145916f0164c4401214ea15afb5b230b1d11a21"
readonly TRAEFIK_REPO="https://traefik.github.io/charts"
readonly TRAEFIK_CHART_VERSION="42.4.1"
readonly TRAEFIK_VERSION="v3.7.19"
readonly TRAEFIK_CHART_SHA256="80ea7246b74d5bcd1f86ac598feca6ba516a110dc0ad9e95dfda28d933b4acdb"

# Images by digest. Envoy Gateway: control plane set in the values below; the
# proxy image is the default compiled into v1.10.0 (api/v1alpha1/shared_types.go).
# Cilium: the chart defaults, already pinned by digest. Traefik: image.digest.
readonly EG_IMAGE="docker.io/envoyproxy/gateway:v1.10.0@sha256:c2243d43518bed91d3ed8c2db849a4b7a14ac9b96eb019f2ab104bb1ca8572b1"
readonly EG_PROXY_IMAGE="docker.io/envoyproxy/envoy:distroless-v1.40.2@sha256:09ca6f2140a61ad8df11779a4a30d52b48433d444466328494f9188c9c35eded"
readonly CILIUM_IMAGE="quay.io/cilium/cilium:v1.20.5@sha256:aa72499f075ad729947ea91b026218aceba24f1a8e4534bf36b8368c7c561526"
readonly CILIUM_OPERATOR_IMAGE="quay.io/cilium/operator-generic:v1.20.5@sha256:c6e7de6665aa9701db86c4fe46828a75a0d167afe084a9ffb5bce34b2c4fa8c4"
readonly CILIUM_ENVOY_IMAGE="quay.io/cilium/cilium-envoy:v1.39.6-1794557904-dee711ff0e84b106edd0abcdd71961af1b870359@sha256:bdef13043ebaa7b9dcd8e3a86be41080bb5369e017cd759a12daf89e2b8fafe7"
readonly TRAEFIK_DIGEST="sha256:a6c0194dda77bcb804824580f36fa7edc56e315b1acfe933366c8b52844a78a4"
readonly TRAEFIK_IMAGE="docker.io/traefik:v3.7.19@$TRAEFIK_DIGEST"
# Test backend (busybox httpd) and the netstat pod, same image as BENCH-003.
readonly BUSYBOX_IMAGE="busybox:1.37.0@sha256:a7dbc319b1438115a207e11930dc4bb3e643dcb3ec0bdd694bb36cd8fad289ec"

readonly CLUSTER="celian-bench-004"
readonly NODE="$CLUSTER-control-plane"
readonly APP_NS="celian-app"
readonly TEST_HOST="celian.test"
readonly MARKER="celian-bench-004 ok"
readonly HOST_HTTP=18080
readonly HOST_HTTPS=18443
readonly NODEPORT_HTTP=30080
readonly NODEPORT_HTTPS=30443
readonly SAMPLES=3
readonly SAMPLE_GAP=10
readonly PAUSE_BETWEEN_RUNS=15
readonly HTTPS_TIMEOUT=120
readonly LOCK_STALE_MINUTES=90

OPTIONS="${OPTIONS:-baseline envoy-gateway cilium traefik}"
RUNS="${RUNS:-3}"
PRELOAD="${PRELOAD:-1}"
IDLE_WAIT="${IDLE_WAIT:-120}"
READY_TIMEOUT="${READY_TIMEOUT:-600}"
LOCK_DIR="${BENCH_LOCK_DIR:-}"
readonly OPTIONS RUNS PRELOAD IDLE_WAIT READY_TIMEOUT LOCK_DIR

TRIAL_DIR=""
LOGS=""
CHARTS=""
GATEWAY_API_LOCAL=""
KIND_NETWORK_EXISTED=0
LOCK_HELD=0
LOCK_STARTED=""

# --- Helpers ------------------------------------------------------------------

log() { printf '[bench-004 %s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die() {
  log "ERROR: $*"
  exit 1
}
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
seconds_between() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", b - a }'; }
utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
sha256_of() { shasum -a 256 "$1" | awk '{ print $1 }'; }

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

kube() { kubectl --request-timeout=10s "$@"; }

gateway_class() {
  case $1 in
    envoy-gateway) echo eg ;;
    cilium) echo cilium ;;
    traefik) echo traefik ;;
  esac
}

# Images the gateway makes the node pull, by digest.
option_images() {
  case $1 in
    envoy-gateway) printf '%s\n' "$EG_IMAGE" "$EG_PROXY_IMAGE" ;;
    cilium) printf '%s\n' "$CILIUM_IMAGE" "$CILIUM_OPERATOR_IMAGE" "$CILIUM_ENVOY_IMAGE" ;;
    traefik) printf '%s\n' "$TRAEFIK_IMAGE" ;;
  esac
}

# --- Lock shared with the other benchmarks -----------------------------------

write_owner() {
  printf 'BENCH-004 %s (series started %s)\n' "$(utc_now)" "$LOCK_STARTED" >"$LOCK_DIR/owner"
}

# Returns 0 with the lock held, 3 when another benchmark holds it.
acquire_lock() {
  local owner_file="$LOCK_DIR/owner"
  [ -n "$LOCK_DIR" ] || return 0
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    if [ -f "$owner_file" ] && [ -n "$(find "$owner_file" -mmin +"$LOCK_STALE_MINUTES" 2>/dev/null)" ]; then
      log "stale lock, older than $LOCK_STALE_MINUTES min, removed: $(cat "$owner_file")"
      rm -f "$owner_file"
      rmdir "$LOCK_DIR" 2>/dev/null || return 3
      mkdir "$LOCK_DIR" 2>/dev/null || return 3
    else
      log "lock held: $(cat "$owner_file" 2>/dev/null || echo 'no owner file yet')"
      return 3
    fi
  fi
  LOCK_HELD=1
  LOCK_STARTED=$(utc_now)
  write_owner
}

# Called at every run: refresh the owner file, and stop if the lock was lost.
refresh_lock() {
  [ "$LOCK_HELD" = 1 ] || return 0
  if [ ! -d "$LOCK_DIR" ] || ! grep -q '^BENCH-004 ' "$LOCK_DIR/owner" 2>/dev/null; then
    LOCK_HELD=0
    die "lock $LOCK_DIR lost: another benchmark may be measuring"
  fi
  write_owner
}

release_lock() {
  [ "$LOCK_HELD" = 1 ] || return 0
  if grep -q '^BENCH-004 ' "$LOCK_DIR/owner" 2>/dev/null; then
    rm -f "$LOCK_DIR/owner"
    rmdir "$LOCK_DIR" 2>/dev/null || log "lock directory not empty, left in place: $LOCK_DIR"
  fi
  LOCK_HELD=0
}

# --- Pinned artefacts ---------------------------------------------------------

fetch_checked() {
  local file=$1 expected=$2 sum
  sum=$(sha256_of "$file")
  [ "$sum" = "$expected" ] || die "$(basename "$file"): SHA-256 $sum differs from the pinned $expected"
  tsv versions.tsv "sha256:$(basename "$file")" "$sum"
}

fetch_artefacts() {
  CHARTS="$TRIAL_DIR/charts"
  mkdir -p "$CHARTS" "$TRIAL_DIR/gateway-api"
  log "downloading the pinned charts and the Gateway API CRDs"
  gh release download "$GATEWAY_API_VERSION" -R "$GATEWAY_API_REPO" -p "$GATEWAY_API_FILE" \
    -D "$TRIAL_DIR/gateway-api" >>"$LOGS/fetch.log" 2>&1 || die "gh release download failed"
  GATEWAY_API_LOCAL="$TRIAL_DIR/gateway-api/$GATEWAY_API_FILE"
  fetch_checked "$GATEWAY_API_LOCAL" "$GATEWAY_CRDS_SHA256"
  case " $OPTIONS " in
    *" envoy-gateway "*)
      helm pull "$EG_CHART" --version "$EG_VERSION" -d "$CHARTS" >>"$LOGS/fetch.log" 2>&1
      helm pull "$EG_CRDS_CHART" --version "$EG_VERSION" -d "$CHARTS" >>"$LOGS/fetch.log" 2>&1
      fetch_checked "$CHARTS/gateway-helm-$EG_VERSION.tgz" "$EG_CHART_SHA256"
      fetch_checked "$CHARTS/gateway-crds-helm-$EG_VERSION.tgz" "$EG_CRDS_CHART_SHA256"
      ;;
  esac
  case " $OPTIONS " in
    *" cilium "*)
      helm pull cilium --repo "$CILIUM_REPO" --version "$CILIUM_VERSION" -d "$CHARTS" >>"$LOGS/fetch.log" 2>&1
      fetch_checked "$CHARTS/cilium-$CILIUM_VERSION.tgz" "$CILIUM_CHART_SHA256"
      ;;
  esac
  case " $OPTIONS " in
    *" traefik "*)
      helm pull traefik --repo "$TRAEFIK_REPO" --version "$TRAEFIK_CHART_VERSION" -d "$CHARTS" >>"$LOGS/fetch.log" 2>&1
      fetch_checked "$CHARTS/traefik-$TRAEFIK_CHART_VERSION.tgz" "$TRAEFIK_CHART_SHA256"
      ;;
  esac
}

# --- Configuration files ------------------------------------------------------

write_kind_configs() {
  local dir="$TRIAL_DIR/kind"
  mkdir -p "$dir"
  printf '%s\n' "kind: Cluster" "apiVersion: kind.x-k8s.io/v1alpha4" "nodes:" \
    "  - role: control-plane" >"$dir/baseline.yaml"
  # Envoy Gateway and Traefik: a NodePort Service with fixed node ports.
  cat >"$dir/nodeport.yaml" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: $NODEPORT_HTTP
        hostPort: $HOST_HTTP
        listenAddress: "127.0.0.1"
      - containerPort: $NODEPORT_HTTPS
        hostPort: $HOST_HTTPS
        listenAddress: "127.0.0.1"
EOF
  # Cilium: it replaces the CNI and kube-proxy, and its Envoy listens on the
  # host network of the node, on the Gateway listener ports.
  cat >"$dir/cilium.yaml" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
  kubeProxyMode: "none"
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 80
        hostPort: $HOST_HTTP
        listenAddress: "127.0.0.1"
      - containerPort: 443
        hostPort: $HOST_HTTPS
        listenAddress: "127.0.0.1"
EOF
}

kind_config() {
  case $1 in
    baseline) echo "$TRIAL_DIR/kind/baseline.yaml" ;;
    cilium) echo "$TRIAL_DIR/kind/cilium.yaml" ;;
    *) echo "$TRIAL_DIR/kind/nodeport.yaml" ;;
  esac
}

write_values() {
  local dir="$TRIAL_DIR/values"
  mkdir -p "$dir"
  cat >"$dir/envoy-gateway-class.yaml" <<EOF
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: celian-local
  namespace: envoy-gateway-system
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyService:
        type: NodePort
        patch:
          type: StrategicMerge
          value:
            spec:
              ports:
                - port: 80
                  nodePort: $NODEPORT_HTTP
                - port: 443
                  nodePort: $NODEPORT_HTTPS
---
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
  parametersRef:
    group: gateway.envoyproxy.io
    kind: EnvoyProxy
    name: celian-local
    namespace: envoy-gateway-system
EOF
  cat >"$dir/cilium.yaml" <<EOF
image:
  pullPolicy: IfNotPresent
ipam:
  mode: kubernetes
kubeProxyReplacement: true
k8sServiceHost: $NODE
k8sServicePort: 6443
operator:
  replicas: 1
gatewayAPI:
  enabled: true
  hostNetwork:
    enabled: true
envoy:
  securityContext:
    capabilities:
      keepCapNetBindService: true
      envoy: [NET_ADMIN, SYS_ADMIN, NET_BIND_SERVICE]
EOF
  cat >"$dir/traefik.yaml" <<EOF
image:
  digest: $TRAEFIK_DIGEST
versionOverride: $TRAEFIK_VERSION
providers:
  kubernetesGateway:
    enabled: true
gateway:
  enabled: false
service:
  spec:
    type: NodePort
ports:
  web:
    port: 80
    nodePort: $NODEPORT_HTTP
  websecure:
    port: 443
    nodePort: $NODEPORT_HTTPS
podSecurityContext:
  runAsGroup: 65532
  runAsNonRoot: true
  runAsUser: 65532
  seccompProfile:
    type: RuntimeDefault
  sysctls:
    - name: net.ipv4.ip_unprivileged_port_start
      value: "0"
EOF
}

# The application side, identical for every option except gatewayClassName.
write_app() {
  local dir="$TRIAL_DIR/app" opt
  mkdir -p "$dir"
  openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=$TEST_HOST" \
    -addext "subjectAltName=DNS:$TEST_HOST" -keyout "$dir/tls.key" -out "$dir/tls.crt" \
    >>"$LOGS/openssl.log" 2>&1 || die "openssl could not create the test certificate"
  cat >"$dir/backend.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata: {name: hello-www, namespace: $APP_NS}
data:
  index.html: "$MARKER"
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: hello, namespace: $APP_NS}
spec:
  replicas: 1
  selector: {matchLabels: {app: hello}}
  template:
    metadata: {labels: {app: hello}}
    spec:
      securityContext: {runAsUser: 65534, runAsNonRoot: true}
      containers:
        - name: httpd
          image: $BUSYBOX_IMAGE
          command: ["httpd", "-f", "-p", "8080", "-h", "/www"]
          ports: [{containerPort: 8080}]
          volumeMounts: [{name: www, mountPath: /www}]
      volumes: [{name: www, configMap: {name: hello-www}}]
---
apiVersion: v1
kind: Service
metadata: {name: hello, namespace: $APP_NS}
spec:
  selector: {app: hello}
  ports: [{port: 8080, targetPort: 8080}]
EOF
  cat >"$dir/gateway.tmpl.yaml" <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: web, namespace: $APP_NS}
spec:
  gatewayClassName: __CLASS__
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes: {namespaces: {from: Same}}
    - name: https
      protocol: HTTPS
      port: 443
      hostname: $TEST_HOST
      tls:
        mode: Terminate
        certificateRefs: [{kind: Secret, name: celian-test-tls}]
      allowedRoutes: {namespaces: {from: Same}}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: hello, namespace: $APP_NS}
spec:
  parentRefs: [{name: web}]
  rules:
    - backendRefs: [{name: hello, port: 8080}]
EOF
  tsv versions.tsv "sha256:gateway.tmpl.yaml" "$(sha256_of "$dir/gateway.tmpl.yaml")"
  for opt in envoy-gateway cilium traefik gke; do
    local class
    class=$(gateway_class "$opt")
    [ "$opt" = gke ] && class=gke-l7-global-external-managed
    sed "s/__CLASS__/$class/" "$dir/gateway.tmpl.yaml" >"$dir/gateway-$opt.yaml"
    tsv versions.tsv "diff-lines:gateway-$opt.yaml" \
      "$(diff "$dir/gateway.tmpl.yaml" "$dir/gateway-$opt.yaml" | grep -c '^[<>]' || true)"
  done
}

# --- Cluster ------------------------------------------------------------------

cluster_containers() {
  docker ps -a --filter "label=io.x-k8s.kind.cluster=$CLUSTER" --format '{{.Names}}' | sort
}

cluster_running() {
  docker ps --filter "label=io.x-k8s.kind.cluster=$CLUSTER" --format '{{.Names}}' | sort
}

delete_cluster() { kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG"; }

wait_gone() {
  local deadline
  deadline=$(($(date +%s) + 180))
  while [ -n "$(cluster_containers)" ]; do
    [ "$(date +%s)" -lt "$deadline" ] || return 1
    sleep 0.5
  done
}

sweep_leftovers() {
  local phase=$1 name
  for name in $(docker network ls --format '{{.Name}}'); do
    if [ "$name" = "$CLUSTER" ]; then
      if docker network rm "$name" >>"$LOGS/leftovers.log" 2>&1; then
        tsv leftovers.tsv "$phase" network "$name" removed
      else
        tsv leftovers.tsv "$phase" network "$name" "left in place"
      fi
    fi
  done
  for name in $(docker volume ls -q); do
    case $name in
      "$CLUSTER" | "$CLUSTER"-*)
        if docker volume rm "$name" >>"$LOGS/leftovers.log" 2>&1; then
          tsv leftovers.tsv "$phase" volume "$name" removed
        else
          tsv leftovers.tsv "$phase" volume "$name" "left in place"
        fi
        ;;
    esac
  done
}

# Every kube-system workload done (same filter as BENCH-003, without k3d).
# shellcheck disable=SC2016 # jq variables, not shell ones
readonly KUBE_SYSTEM_READY='
  [.items[] | select(.kind == "Pod")] as $pods
  | ($pods | length) > 0
  and all($pods[];
      .status.phase == "Succeeded"
      or (.status.phase == "Running"
          and any(.status.conditions[]?; .type == "Ready" and .status == "True")))
  and all(.items[] | select(.kind == "Deployment");
      (.status.availableReplicas // 0) >= .spec.replicas
      and (.status.updatedReplicas // 0) >= .spec.replicas)
  and all(.items[] | select(.kind == "DaemonSet");
      (.status.desiredNumberScheduled // 0) > 0
      and (.status.numberReady // 0) >= .status.desiredNumberScheduled)'

is_ready() {
  local nodes kube_system
  nodes=$(kube get nodes -o json 2>/dev/null) || return 1
  printf '%s' "$nodes" | jq -e '(.items | length) == 1
    and all(.items[]; any(.status.conditions[]?; .type == "Ready" and .status == "True"))' \
    >/dev/null || return 1
  kube_system=$(kube get pods,deployments,daemonsets -n kube-system -o json 2>/dev/null) || return 1
  printf '%s' "$kube_system" | jq -e "$KUBE_SYSTEM_READY" >/dev/null
}

# HTTP/1.1 with "Connection: close". The sleep keeps nc's input open, so the
# client does not half-close before the answer: with HTTP/1.0 and an
# immediate end of input, the smoke tests of 2026-11-19 got no answer from
# Envoy Gateway on the host, while wget got one inside the cluster.
readonly HTTP_REQUEST="GET / HTTP/1.1\r\nHost: $TEST_HOST\r\nConnection: close\r\n\r\n"

http_ok() {
  {
    printf '%b' "$HTTP_REQUEST"
    sleep 0.5
  } | nc -w 2 127.0.0.1 "$HOST_HTTP" 2>/dev/null | grep -q "$MARKER"
}

# openssl s_client as an HTTPS client, with SNI; perl's alarm bounds it.
https_ok() {
  printf '%b' "$HTTP_REQUEST" |
    perl -e 'alarm shift; exec @ARGV' 10 openssl s_client -quiet -ign_eof \
      -connect "127.0.0.1:$HOST_HTTPS" -servername "$TEST_HOST" 2>/dev/null | grep -q "$MARKER"
}

# Prints "<t_nodes_ready>\t<t_http>": polls readiness and HTTP every second.
wait_http() {
  local deadline nodes_t="" t
  deadline=$(($(date +%s) + READY_TIMEOUT))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    t=$(now)
    if [ -z "$nodes_t" ] && is_ready; then nodes_t=$t; fi
    if http_ok; then
      printf '%s\t%s\n' "${nodes_t:-$t}" "$t"
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_https() {
  local deadline
  deadline=$(($(date +%s) + HTTPS_TIMEOUT))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if https_ok; then
      now
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_ready() {
  local deadline streak=0 first="" t
  deadline=$(($(date +%s) + READY_TIMEOUT))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    t=$(now)
    if is_ready; then
      if [ "$streak" -eq 0 ]; then first=$t; fi
      streak=$((streak + 1))
      if [ "$streak" -ge 3 ]; then
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

# --- Install ------------------------------------------------------------------

install_option() {
  local opt=$1 log_file=$2
  case $opt in
    envoy-gateway)
      # Envoy Gateway CRDs only: the Gateway API CRDs are the v1.7.0 standard
      # bundle applied before, not the v1.6.1 experimental copy of the chart.
      helm template eg-crds "$CHARTS/gateway-crds-helm-$EG_VERSION.tgz" \
        --set crds.envoyGateway.enabled=true --set crds.gatewayAPI.enabled=false \
        >"$TRIAL_DIR/values/envoy-gateway-crds.yaml" || return 1
      kube apply --server-side -f "$TRIAL_DIR/values/envoy-gateway-crds.yaml" >>"$log_file" 2>&1 || return 1
      helm install eg "$CHARTS/gateway-helm-$EG_VERSION.tgz" -n envoy-gateway-system \
        --create-namespace --set crds.enabled=false \
        --set "global.images.envoyGateway.image=$EG_IMAGE" >>"$log_file" 2>&1 || return 1
      kube apply -f "$TRIAL_DIR/values/envoy-gateway-class.yaml" >>"$log_file" 2>&1 || return 1
      ;;
    cilium)
      helm install cilium "$CHARTS/cilium-$CILIUM_VERSION.tgz" -n kube-system \
        -f "$TRIAL_DIR/values/cilium.yaml" >>"$log_file" 2>&1 || return 1
      ;;
    traefik)
      helm install traefik "$CHARTS/traefik-$TRAEFIK_CHART_VERSION.tgz" -n traefik \
        --create-namespace -f "$TRIAL_DIR/values/traefik.yaml" >>"$log_file" 2>&1 || return 1
      ;;
  esac
}

apply_app() {
  local opt=$1 log_file=$2 dir="$TRIAL_DIR/app"
  kube create namespace "$APP_NS" >>"$log_file" 2>&1 || return 1
  kube create secret tls celian-test-tls -n "$APP_NS" --cert "$dir/tls.crt" \
    --key "$dir/tls.key" >>"$log_file" 2>&1 || return 1
  kube apply -f "$dir/backend.yaml" >>"$log_file" 2>&1 || return 1
  kube apply -f "$dir/gateway-$opt.yaml" >>"$log_file" 2>&1 || return 1
}

# Pull by tag into the host cache, check the digest, then load into the node.
preload_images() {
  local opt=$1 log_file=$2 ref tagged digest refs=""
  for ref in $(option_images "$opt"); do
    tagged=${ref%@*}
    digest=${ref#*@}
    if ! docker image inspect "$tagged" >/dev/null 2>&1; then
      docker pull -q "$tagged" >>"$log_file" 2>&1 || die "docker pull $tagged failed"
    fi
    case $(docker image inspect --format '{{join .RepoDigests ","}}' "$tagged") in
      *"$digest"*) ;;
      *) die "$tagged in the Docker cache does not carry $digest" ;;
    esac
    refs="$refs $tagged"
  done
  # shellcheck disable=SC2086 # one word per image reference
  kind load docker-image $refs --name "$CLUSTER" >>"$log_file" 2>&1
}

# --- Records ------------------------------------------------------------------

# Load average, this cluster's containers, the containers of other CELIAN
# benchmarks by name, and only a count of the rest: their names belong to
# other projects.
record_load() {
  local opt=$1 phase=$2 loadavg mine bench others total
  loadavg=$(uptime | sed -e 's/.*load average[s]*: //' -e 's/,//g')
  mine=$(cluster_running | paste -sd, -)
  bench=$(docker ps --format '{{.Names}}' | grep '^celian-bench-' | grep -v "^$CLUSTER" | paste -sd, - || true)
  total=$(docker ps -q | wc -l | tr -d ' ')
  others=$(docker ps --format '{{.Names}}' | grep -v -c -e "^$CLUSTER" -e '^celian-bench-' || true)
  tsv load.tsv "$(utc_now)" "$opt" "$phase" "$loadavg" "${mine:--}" "${bench:--}" "$others" "$total"
}

lsof_listeners() {
  lsof -nP -iTCP:"$1" -sTCP:LISTEN 2>/dev/null | awk 'NR > 1 { print $1 "=" $9 }' | sort -u | paste -sd, -
}

record_ports() {
  local opt=$1 phase=$2 server port name ports
  docker ps --filter "label=io.x-k8s.kind.cluster=$CLUSTER" --format '{{.Names}}\t{{.Ports}}' |
    while IFS=$'\t' read -r name ports; do
      tsv ports.tsv "$opt" "$phase" container "$name" "${ports:--}"
    done
  server=$(kube config view --minify -o jsonpath='{.clusters[0].cluster.server}')
  port=${server##*:}
  tsv ports.tsv "$opt" "$phase" api-server "$server" "$(lsof_listeners "$port")"
  for port in $HOST_HTTP $HOST_HTTPS; do
    tsv ports.tsv "$opt" "$phase" host-port "$port" "$(lsof_listeners "$port")"
  done
}

conditions_of() {
  jq -r '[.status.conditions[]? | "\(.type)=\(.status)(\(.reason))"] | join(",")'
}

# GatewayClass, Gateway, listeners and HTTPRoute status, CRD bundle after install.
record_status() {
  local opt=$1 phase=$2 class
  class=$(gateway_class "$opt")
  tsv functional.tsv "$opt" "$phase" gatewayclass "$(kube get gatewayclass "$class" -o json 2>/dev/null | conditions_of)"
  tsv functional.tsv "$opt" "$phase" gateway "$(kube get gateway web -n "$APP_NS" -o json 2>/dev/null | conditions_of)"
  tsv functional.tsv "$opt" "$phase" listeners "$(kube get gateway web -n "$APP_NS" -o json 2>/dev/null |
    jq -r '[.status.listeners[]? | "\(.name):" + ([.conditions[]? | "\(.type)=\(.status)"] | join("/"))] | join(",")')"
  tsv functional.tsv "$opt" "$phase" httproute "$(kube get httproute hello -n "$APP_NS" -o json 2>/dev/null |
    jq -r '[.status.parents[]?.conditions[]? | "\(.type)=\(.status)(\(.reason))"] | join(",")')"
  tsv functional.tsv "$opt" "$phase" gateway-api-crds "$(kube get crd -o json |
    jq -r '[.items[] | select(.spec.group == "gateway.networking.k8s.io")
      | "\(.metadata.name | split(".")[0])=\(.metadata.annotations["gateway.networking.k8s.io/bundle-version"] // "none")/\(.metadata.annotations["gateway.networking.k8s.io/channel"] // "none")"]
      | join(",")')"
}

record_node_images() {
  local opt=$1 phase=$2 status image
  kube get events -A -o json | jq -r '.items[] | select(.reason == "Pulled") | .message' |
    sed -n -e 's/^Successfully pulled image "\([^"]*\)".*/pulled|\1/p' \
      -e 's/^Container image "\([^"]*\)" already present.*/present|\1/p' |
    sort -u | while IFS='|' read -r status image; do
      tsv node-images.tsv "$opt" "$phase" "$status" "$image"
    done
  kube get events -A -o json | jq -r '.items[] | select(.reason == "Pulled") | .message' \
    >>"$LOGS/$opt-$phase-pulled.log" 2>&1 || true
}

to_mib_awk='function to_mib(v,  n, u) {
  n = v; sub(/[A-Za-z]+$/, "", n); u = v; sub(/^[0-9.]+/, "", u)
  if (u == "B") return n / 1048576
  if (u == "KiB" || u == "kB") return n / 1024
  if (u == "MiB" || u == "MB") return n
  if (u == "GiB" || u == "GB") return n * 1024
  return -1 }'

idle_sample() {
  local opt=$1 run=$2 sample=$3 names stats
  read -r -a names <<<"$(cluster_running | tr '\n' ' ')"
  [ "${#names[@]}" -gt 0 ] || die "$opt: no running cluster container to sample"
  stats=$(docker stats --no-stream --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' "${names[@]}")
  printf '%s\n' "$stats" | awk -F'\t' -v opt="$opt" -v run="$run" -v s="$sample" \
    -v out="$TRIAL_DIR/idle-samples.tsv" "$to_mib_awk"'
    { cpu = $2; sub(/%/, "", cpu); split($3, m, " "); mib = to_mib(m[1])
      printf "%s\t%s\t%s\t%s\t%.2f\t%.1f\n", opt, run, s, $1, cpu, mib >> out
      tc += cpu; tm += mib }
    END { printf "%.2f\t%.1f\n", tc, tm }'
}

# Per pod memory (working set) and CPU from the kubelet stats summary API.
record_pods() {
  local opt=$1 run=$2
  kube get --raw "/api/v1/nodes/$NODE/proxy/stats/summary" 2>/dev/null |
    jq -r --arg o "$opt" --arg r "$run" '.pods[] | [$o, $r, .podRef.namespace, .podRef.name,
      (((.memory.workingSetBytes // 0) / 1048576) * 10 | floor / 10),
      (((.cpu.usageNanoCores // 0) / 1000000) | floor)] | @tsv' >>"$TRIAL_DIR/pods.tsv" || true
}

# Sockets listening inside the node network namespace, from a hostNetwork pod.
record_node_listeners() {
  local opt=$1 phase=$2 log_file=$3
  kube run netstat -n "$APP_NS" --image="$BUSYBOX_IMAGE" --restart=Never \
    --overrides='{"apiVersion":"v1","spec":{"hostNetwork":true}}' --command -- netstat -tln \
    >>"$log_file" 2>&1 || return 0
  kube wait -n "$APP_NS" --for=jsonpath='{.status.phase}'=Succeeded pod/netstat --timeout=90s \
    >>"$log_file" 2>&1 || return 0
  kube logs -n "$APP_NS" netstat 2>/dev/null | awk '$1 ~ /^tcp/ { print $4 }' | sort -u |
    while read -r addr; do tsv ports.tsv "$opt" "$phase" node-listen "$addr" "-"; done
}

# Compressed size per architecture (layers plus config) from the registry
# manifest, read by digest with docker manifest inspect: no pull.
registry_sizes() {
  local repo_tag query sizes
  repo_tag=${1%@*}
  query="${repo_tag%:*}@${1#*@}"
  sizes=$(docker manifest inspect -v "$query" 2>/dev/null | jq -r '
    [if type == "array" then .[] else . end
     | select(.Descriptor.platform.os == "linux")
     | (.SchemaV2Manifest // .OCIManifest) as $m
     | "\(.Descriptor.platform.architecture)=\(([$m.layers[]?.size] | add) + ($m.config.size // 0))"]
    | map(select(startswith("arm64=") or startswith("amd64="))) | join(",")' 2>/dev/null || true)
  echo "${sizes:--}"
}

record_images() {
  local opt=$1 ref
  for ref in $(option_images "$opt"); do
    tsv images.tsv "$opt" "$ref" "$(registry_sizes "$ref")"
  done
}

# --- One run ------------------------------------------------------------------

run_once() {
  local opt=$1 run=$2 mode=$3 log_file t0 t1 t_loaded t_installed times t_nodes t_http
  local t_https="" cpu mem samples="" i sample pulls version started
  log_file="$LOGS/$opt-run-$run.log"
  refresh_lock
  record_load "$opt" "run-$run"
  if should_preload "$opt" "$mode"; then
    log "$opt run $run: pulling the gateway images into the host cache (not timed)"
    preload_images_host "$opt" "$log_file"
  fi
  log "$opt run $run ($mode): create"
  started=$(utc_now)
  t0=$(now)
  kind create cluster --name "$CLUSTER" --image "$KIND_IMAGE" --kubeconfig "$KUBECONFIG" \
    --config "$(kind_config "$opt")" >"$log_file" 2>&1 || die "$opt create failed, see $log_file"
  t1=$(now)
  t_loaded=$t1
  if [ "$opt" = baseline ]; then
    t_http=$(wait_ready) || die "baseline not ready after ${READY_TIMEOUT}s"
    t_nodes=$t_http
    t_installed=$t1
  else
    if should_preload "$opt" "$mode"; then
      preload_images "$opt" "$log_file"
      t_loaded=$(now)
    fi
    kube apply --server-side -f "$GATEWAY_API_LOCAL" >>"$log_file" 2>&1 || die "$opt: Gateway API CRDs not applied"
    kube wait --for=condition=Established --timeout=60s crd/gatewayclasses.gateway.networking.k8s.io \
      crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io >>"$log_file" 2>&1
    install_option "$opt" "$log_file" || die "$opt install failed, see $log_file"
    t_installed=$(now)
    apply_app "$opt" "$log_file" || die "$opt: application manifests not applied, see $log_file"
    if times=$(wait_http); then
      t_nodes=$(printf '%s' "$times" | cut -f1)
      t_http=$(printf '%s' "$times" | cut -f2)
    else
      record_status "$opt" "run-$run"
      die "$opt: no HTTP answer on 127.0.0.1:$HOST_HTTP after ${READY_TIMEOUT}s"
    fi
    log "$opt run $run: HTTP answer in $(seconds_between "$t0" "$t_http") s"
    t_https=$(wait_https) || t_https=""
    record_status "$opt" "run-$run"
  fi
  record_ports "$opt" "run-$run"
  if [ "$opt" != baseline ] && [ "$run" = 1 ]; then
    record_node_listeners "$opt" "run-$run" "$log_file"
    tsv functional.tsv "$opt" "run-$run" tls-subject "$(perl -e 'alarm shift; exec @ARGV' 10 \
      openssl s_client -connect "127.0.0.1:$HOST_HTTPS" -servername "$TEST_HOST" </dev/null 2>/dev/null |
      openssl x509 -noout -subject 2>/dev/null || echo none)"
  fi

  sleep "$(awk -v t="$t_http" -v w="$IDLE_WAIT" -v n="$(now)" 'BEGIN { d = t + w - n; printf "%.1f", (d > 0 ? d : 0) }')"
  for i in $(seq 1 "$SAMPLES"); do
    sample=$(idle_sample "$opt" "$run" "$i")
    samples="$samples$sample"$'\n'
    if [ "$i" -eq 2 ]; then record_pods "$opt" "$run"; fi
    if [ "$i" -lt "$SAMPLES" ]; then sleep "$SAMPLE_GAP"; fi
  done
  cpu=$(printf '%s' "$samples" | cut -f1 | grep . | median_range | cut -f1)
  mem=$(printf '%s' "$samples" | cut -f2 | grep . | median_range | cut -f1)
  version=$(kube version -o json | jq -r '.serverVersion.gitVersion')
  pulls=$(kube get events -A -o json | jq -r '[.items[] | select(.reason == "Pulled") | .message] |
    "\(map(select(test("Successfully pulled"))) | length)\t\(map(select(test("already present"))) | length)"')
  record_node_images "$opt" "run-$run"

  log "$opt run $run: delete"
  delete_cluster >>"$log_file" 2>&1 || die "$opt delete failed, see $log_file"
  wait_gone || die "$opt containers still present after delete"
  sweep_leftovers "$opt-run-$run"

  local https_s="-"
  if [ -n "$t_https" ]; then https_s=$(seconds_between "$t0" "$t_https"); fi
  tsv runs.tsv "$opt" "$run" "$mode" "$(seconds_between "$t0" "$t1")" \
    "$(seconds_between "$t1" "$t_loaded")" "$(seconds_between "$t0" "$t_nodes")" \
    "$(seconds_between "$t0" "$t_installed")" "$(seconds_between "$t0" "$t_http")" \
    "$https_s" "$mem" "$cpu" "$pulls" "$version" "$started"
}

# Host cache only: the pull before the timer of a warm run.
preload_images_host() {
  local opt=$1 log_file=$2 ref tagged
  for ref in $(option_images "$opt"); do
    tagged=${ref%@*}
    if ! docker image inspect "$tagged" >/dev/null 2>&1; then
      docker pull -q "$tagged" >>"$log_file" 2>&1 || die "docker pull $tagged failed"
    fi
    tsv images.tsv "$opt" "host-cache:$tagged" \
      "$(docker image inspect --format '{{.Size}} {{join .RepoDigests ","}}' "$tagged")"
  done
}

should_preload() { [ "$1" != baseline ] && [ "$2" = warm ] && [ "$PRELOAD" = 1 ]; }

series() {
  local opt=$1 run=0
  if [ "$opt" = baseline ]; then run=1; fi
  record_images "$opt"
  while [ "$run" -le "$RUNS" ]; do
    if [ "$run" -eq 0 ]; then
      run_once "$opt" 0 cold
    else
      run_once "$opt" "$run" warm
    fi
    sleep "$PAUSE_BETWEEN_RUNS"
    run=$((run + 1))
  done
}

# --- Start-up checks ----------------------------------------------------------

check_versions() {
  local v
  for v in docker kind kubectl helm gh jq perl nc lsof openssl shasum; do
    command -v "$v" >/dev/null || die "$v not found"
  done
  v=$(kind version | awk '{ print $2 }')
  [ "$v" = "$KIND_VERSION" ] || die "kind $v found, $KIND_VERSION expected"
  tsv versions.tsv kind "$v"
  v=$(kubectl version --client -o json | jq -r '.clientVersion.minor' | tr -dc '0-9')
  case " $KUBECTL_MINORS " in
    *" $v "*) ;;
    *) die "kubectl 1.$v is more than one minor away from the node image" ;;
  esac
  tsv versions.tsv kubectl "$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion')"
  tsv versions.tsv helm "$(helm version --template '{{.Version}}')"
  tsv versions.tsv docker "$(docker version --format '{{.Server.Version}}')"
  tsv versions.tsv engine "$(docker info --format '{{.OperatingSystem}} {{.NCPU}} CPU {{.MemTotal}} B cgroup v{{.CgroupVersion}} {{.Driver}}')"
  tsv versions.tsv host "$(sysctl -n hw.model 2>/dev/null || uname -m) $(sw_vers -productVersion 2>/dev/null || uname -r)"
  tsv versions.tsv openssl "$(openssl version)"
}

check_start() {
  local port
  [ -z "$(cluster_containers)" ] || die "a kind cluster named $CLUSTER already exists"
  [ -z "$(docker ps -aq --filter "name=^/?$CLUSTER")" ] || die "a container named $CLUSTER* already exists"
  for port in $HOST_HTTP $HOST_HTTPS; do
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then die "port $port is already in use"; fi
  done
}

# --- Cleanup ------------------------------------------------------------------

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  set +e
  if [ -n "$(cluster_containers)" ]; then
    log "cleanup: deleting the kind cluster $CLUSTER"
    delete_cluster >>"$LOGS/cleanup.log" 2>&1
    wait_gone
  fi
  sweep_leftovers cleanup
  if [ "$KIND_NETWORK_EXISTED" = 0 ] && docker network inspect kind >/dev/null 2>&1 &&
    [ "$(docker network inspect kind --format '{{len .Containers}}')" = 0 ]; then
    log "cleanup: removing the kind network created by this run"
    docker network rm kind >>"$LOGS/cleanup.log" 2>&1
  fi
  release_lock
  docker volume ls -q | sort >"$TRIAL_DIR/volumes-after.txt"
  log "results in $TRIAL_DIR"
  exit "$rc"
}

summarize() {
  local opt column name values
  tsv summary.tsv option metric runs values median range
  for opt in $OPTIONS; do
    for column in 8:http_s 6:nodes_ready_s 9:https_s 10:mem_mib 11:cpu_pct 4:create_cmd_s; do
      name=${column#*:}
      values=$(awk -F'\t' -v o="$opt" -v c="${column%%:*}" \
        '$1 == o && $3 == "warm" && $c != "-" { print $c }' "$TRIAL_DIR/runs.tsv")
      tsv summary.tsv "$opt" "$name" "$(printf '%s\n' "$values" | grep -c .)" \
        "$(printf '%s\n' "$values" | paste -sd, -)" "$(printf '%s\n' "$values" | median_range)"
    done
  done
}

# --- Main ---------------------------------------------------------------------

main() {
  local opt rc=0
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
  TRIAL_DIR=$(cd "$TRIAL_DIR" && pwd)
  LOGS="$TRIAL_DIR/logs"
  mkdir -p "$LOGS"
  export KUBECONFIG="$TRIAL_DIR/kubeconfig"
  export HELM_CACHE_HOME="$TRIAL_DIR/helm/cache"
  export HELM_CONFIG_HOME="$TRIAL_DIR/helm/config"
  export HELM_DATA_HOME="$TRIAL_DIR/helm/data"
  : >"$KUBECONFIG"
  chmod 600 "$KUBECONFIG"

  tsv runs.tsv option run mode create_cmd_s preload_s nodes_ready_s installed_s http_s https_s \
    mem_mib cpu_pct pulled_downloaded pulled_present k8s_version started_utc
  tsv idle-samples.tsv option run sample container cpu_pct mem_mib
  tsv pods.tsv option run namespace pod mem_mib cpu_millicores
  tsv ports.tsv option phase kind name listeners
  tsv images.tsv option image compressed_bytes_or_host_cache
  tsv node-images.tsv option phase status image
  tsv functional.tsv option phase check result
  tsv load.tsv utc option phase loadavg_1_5_15 cluster_containers other_celian_bench other_containers total_containers
  tsv leftovers.tsv phase type name action
  tsv versions.tsv item version

  # Start-up checks and artefacts first, without any trap: a refusal to start
  # must not delete anything.
  check_versions
  check_start
  fetch_artefacts
  write_kind_configs
  write_values
  write_app
  acquire_lock || rc=$?
  if [ "$rc" -ne 0 ]; then
    log "another benchmark holds the lock: nothing measured, retry later"
    exit "$rc"
  fi
  # Checked again under the lock: a cluster of that name or a busy port may
  # have appeared meanwhile. In a subshell, so that a refusal can still
  # release the lock, since the trap is not set yet.
  if ! (check_start); then
    release_lock
    die "start-up checks failed once the lock was taken: nothing measured"
  fi
  if docker network inspect kind >/dev/null 2>&1; then KIND_NETWORK_EXISTED=1; fi
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  docker volume ls -q | sort >"$TRIAL_DIR/volumes-before.txt"
  log "trial directory: $TRIAL_DIR"

  for opt in $OPTIONS; do
    case $opt in
      baseline | envoy-gateway | cilium | traefik) series "$opt" ;;
      *) die "unknown option: $opt" ;;
    esac
  done
  summarize
  column -t -s "$(printf '\t')" "$TRIAL_DIR/summary.tsv" >&2 || true
}

main "$@"
