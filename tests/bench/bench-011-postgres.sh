#!/usr/bin/env bash
# BENCH-011: Postgres in the local kind cluster of the generated project.
# Options:
#   statefulset  the official postgres image in a StatefulSet written by hand,
#                one PVC from the default StorageClass of kind;
#   cnpg         CloudNativePG, operator installed from its release manifest,
#                one Cluster with one instance;
#   zalando      the Zalando Postgres Operator, installed from the kustomize
#                manifests of its release, one postgresql with one instance;
#   none         the base node: kind alone, same image and configuration
#                (memory baseline of M2, measured in the same series).
# Every manifest is checked against a pinned SHA-256 and every image is
# rewritten to a pinned digest before use. Each run creates a fresh kind
# cluster (kind 0.33.0, node image pinned by digest, as in ADR-004) and
# measures, for one option:
#   - installation until "ready": from the first kubectl apply of the layer
#     (operator included) to the first of three successful authenticated
#     "SELECT 1" through the Service the application would use, run with
#     kubectl exec in a client pod of the cluster (one try per second);
#   - memory and CPU at rest, IDLE_WAIT seconds after "ready", client pod
#     scaled to zero: the node container from docker stats, the layer's pods
#     from the kubelet Summary API (3 samples, 10 s apart);
#   - data kept: one row written, read back after (a) deleting the Postgres
#     pod, (b) applying the layer again, (c) deleting the object that carries
#     Postgres and applying it again, cluster kept;
#   - the server version, and whether the password of the Secret created by
#     the script (by a pipe, ADR-007) is the one the server accepts;
#   - with NODE_RESTART=1: a row written just before "docker stop" of the
#     node, then "docker start", the time until the cluster and Postgres are
#     ready again, and whether the row and the Secret survived.
# Runs are interleaved (option A, option B, ..., then the next run).
# On macOS, each run starts only on AC power with the lid open, and a run
# during which "pmset -g log" shows a Sleep entry is marked invalid
# (power.tsv) and left out of the summary.
#
# Usage: tests/bench/bench-011-postgres.sh [TRIAL_DIR]
#   TRIAL_DIR, if given, must be missing or empty (default: a new mktemp -d).
#   Environment:
#     OPTIONS="none statefulset cnpg zalando"  options, interleaved in order
#     RUNS=3            runs per option
#     IDLE_WAIT=120     seconds between "ready" and the first sample
#     BENCH_LOCK=DIR    optional lock directory shared with other benchmarks:
#                       created with mkdir right after the start-up checks
#                       (exit code 75 if it exists), holds an "owner" file,
#                       removed by the EXIT trap
#     NODE_RESTART=0    1 adds a node restart (docker stop, then docker start
#                       of the node container) after the data checks. Off by
#                       default: "docker start" needs Lucas's approval, given
#                       on 2026-11-21 for the BENCH-011 node only.
#   Results (TSV) in TRIAL_DIR: versions.tsv, manifests.tsv, images.tsv,
#   runs.tsv, idle-pods.tsv, node-images.tsv, data.tsv, restart.tsv,
#   power.tsv, load.tsv, summary.tsv; command output in TRIAL_DIR/logs/.
# Needs: bash >= 3.2, docker, kind v0.33.0, kubectl (1.35 to 1.37), gh, jq,
#   shasum, awk, sed, and a sub-second clock: GNU date, gdate or zsh. No perl
#   and no python. On macOS, pmset and ioreg for the power checks.
#
# Safety:
#   - the cluster is named celian-bench-011. The script refuses to start if it
#     already exists. Its EXIT trap is set only after the start-up checks, so a
#     refusal deletes nothing; afterwards it deletes only that cluster;
#   - umask 077; KUBECONFIG points into TRIAL_DIR: ~/.kube is neither read nor
#     written;
#   - no port is published to the host: kind keeps its API on 127.0.0.1 and
#     every check runs from a pod inside the cluster (no curl, no docker run,
#     no docker exec);
#   - the database password is drawn from /dev/urandom and piped to
#     kubectl create -f -: never in a file, a variable or an argument;
#   - nothing is built and no image is removed: the node pulls every image.
# Side effects outside TRIAL_DIR: the "kind" Docker network, removed at the
#   end if the script created it and nothing uses it. The node pulls the
#   images from docker.io and ghcr.io at every run.
# Commands that create, change or remove a container or a network,
# reviewed by [SECU] before the first run:
#   kind create cluster      (create_cluster) starts the node with
#                            "docker run --privileged", creates the "kind"
#                            network if missing
#   kind delete cluster      (delete_cluster, cleanup) removes the node
#   docker network rm kind   (cleanup) only if this run created it and it
#                            is empty
#   docker stop/docker start (NODE_RESTART=1 only) the node container
#                            celian-bench-011-control-plane, nothing else
# Every other docker call only reads: ps, stats, manifest inspect,
# network inspect, version, info. Host reads on macOS, no change made:
#   pmset -g ps, pmset -g log (power source, battery, Sleep entries),
#   ioreg -r -k AppleClamshellState (lid state).
set -euo pipefail
umask 077

# --- Pinned versions ----------------------------------------------------------

readonly KIND_VERSION="v0.33.0"
readonly KIND_IMAGE="kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed"
readonly KUBECTL_MINORS="35 36 37"

# Option 1: official image, tag 18.7-trixie (Debian), read on 2026-11-20.
readonly PG_IMAGE="docker.io/library/postgres:18.7-trixie@sha256:eb63372c1e05c755f55fa30cbd07aecc443676fc6c0fa90b9002d01537841e1a"

# Option 2: CloudNativePG 1.30.2, release asset cnpg-1.30.2.yaml (the
# documented "operator manifest"), and the minimal operand image for 18.7.
readonly CNPG_VERSION="v1.30.2"
readonly CNPG_SHA256="ea4cc355b394e10661d30c6b409cefb19029dd973bccb76b1ed8c789985bc68c"
readonly CNPG_OPERAND="ghcr.io/cloudnative-pg/postgresql:18.7-minimal-trixie@sha256:635bfde0a4ce2a04daad754e1ad37fb95ae096c8153b37fe1a4561b5ea417e38"

# Option 3: Zalando Postgres Operator v2.0.3, the four files of
# manifests/kustomization.yaml at the commit of tag v2.0.3.
readonly ZALANDO_VERSION="v2.0.3"
readonly ZALANDO_COMMIT="80b7a074ada5221dc5eeac487c19faf810eb9cfe"
readonly ZALANDO_FILES="
kustomization.yaml -
configmap.yaml bb4236da61aa197b7736a3e04f227e74d4e3a31400f7a2da043597a92218cc4c
operator-service-account-rbac.yaml e2afc6cb25d38bcd3720ba7469d0f917deaec2189eedb85275e1b2024dfa650c
postgres-operator.yaml b54d63e178d7d2c15a6bf1c2057f0a6fe79f8a59f54f103b6f80e2a12482cf1f
api-service.yaml 1952b75ab0f18994eaca061161ee612e52cef8fde88d06558ea54b55d5b7fac1
"
readonly ZALANDO_KUSTOMIZATION_SHA256="e9d817d6935cdf3272705baf9a8e6a613e0775ad8bc76a0e2d45c29158137dea"

# Index digest of every image the manifests name, read on 2026-11-20 with
# `docker buildx imagetools inspect`. Each reference of a verified manifest
# (after "image:" or as a value) becomes "REF@DIGEST"; an image left without
# a digest stops the script.
readonly IMAGE_PINS="
ghcr.io/cloudnative-pg/cloudnative-pg:1.30.2 sha256:f96f6be3d81ec93819b443c665c575c609342fca840df90d4d87dae314a5b913
ghcr.io/zalando/postgres-operator:v2.0.3 sha256:2d3a7ca3950f8583fc16addaee94037dd6cd9e5b3f13836c486c958b2f228443
ghcr.io/zalando/spilo-18:4.1-p2 sha256:258a87d34699387f3b6b45d30874c21c6b838ed51c9371ae2a70151d57137990
ghcr.io/zalando/postgres-operator/pgbouncer:v2.0.3 sha256:3857bf8f9c6e950110b79a27b1dbfe666c02ba29ba92abd0ae105062806d787d
ghcr.io/zalando/postgres-operator/logical-backup:v2.0.3 sha256:b5f7dbfe4b43bbcb296ededf16c1394232db888be4bf03e13f979b54f04eaf49
"

# Variants read at the registry for the sensitivity analysis, never pulled.
readonly VARIANT_IMAGES="
docker.io/library/postgres:18.7-alpine@sha256:ff64c9e3bdf8e2120107d3559de8db314e8305f7e38c5105903c6295876738ff
ghcr.io/cloudnative-pg/postgresql:18.7-standard-trixie@sha256:5827829071060876c4029650c04183e4ee562da3ebb9e88c914d67c8dc8669d6
ghcr.io/cloudnative-pg/postgresql:18.7-system-trixie@sha256:b4bbd2e623f1a8833e9a2a4210480ef215b6d13fc0988b06786a778a5c699a20
"

readonly CLUSTER="celian-bench-011"
readonly NODE="$CLUSTER-control-plane"
readonly NS="bench-db"
readonly SAMPLES=3
readonly SAMPLE_GAP=10
readonly PAUSE_BETWEEN_RUNS=15
readonly READY_STREAK=3
readonly CLUSTER_TIMEOUT=300
readonly READY_TIMEOUT=600
readonly APPLY_TIMEOUT=300

OPTIONS="${OPTIONS:-none statefulset cnpg zalando}"
RUNS="${RUNS:-3}"
IDLE_WAIT="${IDLE_WAIT:-120}"
BENCH_LOCK="${BENCH_LOCK:-}"
NODE_RESTART="${NODE_RESTART:-0}"
readonly OPTIONS RUNS IDLE_WAIT BENCH_LOCK NODE_RESTART

TRIAL_DIR=""
LOGS=""
LOCK_HELD=0
KIND_NETWORK_EXISTED=0
CLOCK=""
RUN_POWER_START=""
RUN_POWER_STATE="n/a"
LAST_READY_AT=""

# --- Helpers ------------------------------------------------------------------

log() { printf '[bench-011 %s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die() {
  log "ERROR: $*"
  exit 1
}

# Sub-second clock without perl or python: GNU date, then gdate, then the
# EPOCHREALTIME variable of zsh. Chosen once by pick_clock.
pick_clock() {
  if date +%s.%N | grep -Eq '^[0-9]+\.[0-9]+$'; then
    CLOCK="date"
  elif command -v gdate >/dev/null; then
    CLOCK="gdate"
  elif command -v zsh >/dev/null; then
    CLOCK="zsh"
  else
    die "no sub-second clock: GNU date, gdate or zsh needed"
  fi
}

now() {
  case $CLOCK in
    date) date +%s.%N ;;
    gdate) gdate +%s.%N ;;
    zsh) zsh -fc 'zmodload zsh/datetime && print -r -- $EPOCHREALTIME' ;;
  esac
}
seconds_between() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", b - a }'; }
utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

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

kube() { kubectl --request-timeout=20s "$@"; }

# Print the time of the first of READY_STREAK consecutive successes of a
# command, polled every second, or fail after TIMEOUT seconds.
wait_streak() {
  local timeout=$1 deadline streak=0 first="" t
  shift
  deadline=$(($(date +%s) + timeout))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    t=$(now)
    if "$@"; then
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

# Retry a command once per second until it succeeds (webhooks and CRDs that
# are not served yet), or fail after APPLY_TIMEOUT seconds.
retry() {
  local deadline
  deadline=$(($(date +%s) + APPLY_TIMEOUT))
  until "$@"; do
    [ "$(date +%s)" -lt "$deadline" ] || return 1
    sleep 1
  done
}

# --- Options ------------------------------------------------------------------

option_version() {
  case $1 in
    statefulset) echo "postgres 18.7-trixie" ;;
    cnpg) echo "$CNPG_VERSION" ;;
    zalando) echo "$ZALANDO_VERSION" ;;
    none) echo "-" ;;
  esac
}

# Namespaces whose pods belong to the layer (the client pod is excluded by
# name). The Zalando operator runs in "default", as in its manifests.
layer_namespaces() {
  case $1 in
    statefulset) echo "$NS" ;;
    cnpg) echo "cnpg-system $NS" ;;
    zalando) echo "default $NS" ;;
    none) echo "" ;;
  esac
}

# Image of the client pod: the option's own server image, already pulled by
# the node, so that the client adds no download.
client_image() {
  case $1 in
    statefulset) echo "$PG_IMAGE" ;;
    cnpg) echo "$CNPG_OPERAND" ;;
    zalando) pin_of "ghcr.io/zalando/spilo-18:4.1-p2" ;;
  esac
}

# Service the application would use, and the Secret that holds the password.
db_host() {
  case $1 in
    statefulset) echo "postgres" ;;
    cnpg) echo "bench-rw" ;;
    zalando) echo "acid-bench" ;;
  esac
}

db_secret() {
  case $1 in
    statefulset | cnpg) echo "db-auth" ;;
    zalando) echo "app.acid-bench.credentials.postgresql.acid.zalan.do" ;;
  esac
}

db_pod() {
  case $1 in
    statefulset) echo "postgres-0" ;;
    cnpg) echo "bench-1" ;;
    zalando) echo "acid-bench-0" ;;
  esac
}

pin_of() {
  local ref=$1 r d
  while read -r r d; do
    if [ "$r" = "$ref" ]; then
      echo "$r@$d"
      return 0
    fi
  done <<EOF
$IMAGE_PINS
EOF
  return 1
}

# --- Manifests ------------------------------------------------------------------

manifest_dir() { echo "$TRIAL_DIR/manifests/$1"; }

check_sum() {
  local file=$1 expected=$2 sum
  sum=$(shasum -a 256 "$file" | awk '{ print $1 }')
  [ "$sum" = "$expected" ] || die "$(basename "$file"): SHA-256 $sum differs from $expected"
  echo "$sum"
}

# Rewrite every pinned reference, after "image:" or as a whole value, with
# sed alone. The reference is escaped for an extended regular expression;
# "#" is the sed delimiter, absent from image references.
pin_images() {
  local file=$1 ref digest ref_re
  while read -r ref digest; do
    [ -n "$ref" ] || continue
    ref_re=$(printf '%s' "$ref" | sed 's/[][\.*^$+?(){}|/]/\\&/g')
    sed -E "s#^([[:space:]]*(-[[:space:]]+)?(image|value|[a-z_]+_image):[[:space:]]+\"?)${ref_re}(\"?)[[:space:]]*\$#\\1${ref}@${digest}\\4#" \
      "$file" >"$file.pinned"
    mv "$file.pinned" "$file"
  done <<EOF
$IMAGE_PINS
EOF
}

# Every image reference of a manifest: "image:" fields and *_image values.
manifest_images() {
  sed -n -E \
    -e 's/^[[:space:]]*(-[[:space:]]+)?image:[[:space:]]+"?([^"[:space:]]+)"?[[:space:]]*$/\2/p' \
    -e 's/^[[:space:]]*[a-z_]*_image:[[:space:]]+"?([^"[:space:]]+)"?[[:space:]]*$/\1/p' \
    -e 's/^[[:space:]]*value:[[:space:]]+"?([a-z0-9.-]+\.[a-z]+\/[^"[:space:]]+)"?[[:space:]]*$/\1/p' \
    "$@" | sort -u
}

check_pinned() {
  local opt=$1 unpinned
  shift
  unpinned=$(manifest_images "$@" | grep -v '@sha256:' || true)
  [ -z "$unpinned" ] || die "$opt: images without a pinned digest: $(printf '%s' "$unpinned" | paste -sd, -)"
}

fetch_cnpg() {
  local dir sum
  dir=$(manifest_dir cnpg)
  mkdir -p "$dir"
  gh release download "$CNPG_VERSION" -R cloudnative-pg/cloudnative-pg \
    -p "cnpg-${CNPG_VERSION#v}.yaml" -D "$dir" >>"$LOGS/manifests.log" 2>&1 ||
    die "cnpg: manifest download failed"
  mv "$dir/cnpg-${CNPG_VERSION#v}.yaml" "$dir/operator.yaml"
  sum=$(check_sum "$dir/operator.yaml" "$CNPG_SHA256")
  pin_images "$dir/operator.yaml"
  check_pinned cnpg "$dir/operator.yaml"
  tsv manifests.tsv cnpg "$CNPG_VERSION" operator.yaml "$sum"
}

fetch_zalando() {
  local dir file expected sum
  dir=$(manifest_dir zalando)
  mkdir -p "$dir/operator"
  while read -r file expected; do
    [ -n "$file" ] || continue
    gh api -H 'Accept: application/vnd.github.raw' \
      "repos/zalando/postgres-operator/contents/manifests/$file?ref=$ZALANDO_COMMIT" \
      >"$dir/operator/$file" 2>>"$LOGS/manifests.log" || die "zalando: $file download failed"
    if [ "$expected" = - ]; then expected=$ZALANDO_KUSTOMIZATION_SHA256; fi
    sum=$(check_sum "$dir/operator/$file" "$expected")
    tsv manifests.tsv zalando "$ZALANDO_VERSION" "$file" "$sum"
  done <<EOF
$ZALANDO_FILES
EOF
  pin_images "$dir/operator/configmap.yaml"
  pin_images "$dir/operator/postgres-operator.yaml"
  check_pinned zalando "$dir/operator/configmap.yaml" "$dir/operator/postgres-operator.yaml"
}

write_layer() {
  local opt=$1 dir
  dir=$(manifest_dir "$opt")
  mkdir -p "$dir"
  case $opt in
    statefulset) statefulset_manifest >"$dir/postgres.yaml" ;;
    cnpg) cnpg_cluster_manifest >"$dir/postgres.yaml" ;;
    zalando) zalando_cluster_manifest >"$dir/postgres.yaml" ;;
  esac
  client_manifest "$opt" >"$dir/client.yaml"
  check_pinned "$opt" "$dir/postgres.yaml" "$dir/client.yaml"
}

namespace_manifest() {
  cat <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $NS
EOF
}

# Option 1. The password and the user name come from files of the Secret
# (POSTGRES_PASSWORD_FILE, POSTGRES_USER_FILE of the official image); data
# under /var/lib/postgresql, the volume of the image from PostgreSQL 18 on.
statefulset_manifest() {
  cat <<EOF
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: $NS
spec:
  selector: {app: postgres}
  ports: [{port: 5432, targetPort: 5432}]
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: $NS
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels: {app: postgres}
  template:
    metadata:
      labels: {app: postgres}
    spec:
      securityContext: {runAsNonRoot: true, runAsUser: 999, runAsGroup: 999, fsGroup: 999}
      containers:
        - name: postgres
          image: $PG_IMAGE
          ports: [{containerPort: 5432}]
          env:
            - {name: POSTGRES_USER_FILE, value: /run/secrets/db/username}
            - {name: POSTGRES_PASSWORD_FILE, value: /run/secrets/db/password}
            - {name: POSTGRES_DB, value: app}
          readinessProbe:
            exec: {command: [pg_isready, -U, app, -d, app]}
            periodSeconds: 2
          securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}}
          volumeMounts:
            - {name: data, mountPath: /var/lib/postgresql}
            - {name: auth, mountPath: /run/secrets/db, readOnly: true}
      volumes:
        - name: auth
          secret: {secretName: db-auth, defaultMode: 0440}
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: [ReadWriteOnce]
        resources:
          requests: {storage: 1Gi}
EOF
}

cnpg_cluster_manifest() {
  cat <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: bench
  namespace: $NS
spec:
  instances: 1
  imageName: $CNPG_OPERAND
  storage:
    size: 1Gi
  bootstrap:
    initdb:
      database: app
      owner: app
      secret:
        name: db-auth
EOF
}

zalando_cluster_manifest() {
  cat <<EOF
apiVersion: acid.zalan.do/v1
kind: postgresql
metadata:
  name: acid-bench
  namespace: $NS
spec:
  teamId: acid
  numberOfInstances: 1
  volume:
    size: 1Gi
  users:
    app: []
  databases:
    app: app
  postgresql:
    version: "18"
EOF
}

client_manifest() {
  local opt=$1
  cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgclient
  namespace: $NS
spec:
  replicas: 1
  selector:
    matchLabels: {app: pgclient}
  template:
    metadata:
      labels: {app: pgclient}
    spec:
      terminationGracePeriodSeconds: 1
      containers:
        - name: pgclient
          image: $(client_image "$opt")
          command: [sh, -c, "trap 'exit 0' TERM; while :; do sleep 1; done"]
          env:
            - {name: PGHOST, value: $(db_host "$opt")}
            - {name: PGPORT, value: "5432"}
            - {name: PGDATABASE, value: app}
            - {name: PGCONNECT_TIMEOUT, value: "3"}
            - {name: PGUSER, valueFrom: {secretKeyRef: {name: $(db_secret "$opt"), key: username}}}
            - {name: PGPASSWORD, valueFrom: {secretKeyRef: {name: $(db_secret "$opt"), key: password}}}
EOF
}

# The password never leaves a pipe: /dev/urandom, then kubectl create -f -.
create_secret() {
  local name=$1
  {
    printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: %s\n  namespace: %s\n' "$name" "$NS"
    printf 'type: kubernetes.io/basic-auth\nstringData:\n  username: app\n  password: '
    LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 40
    printf '\n'
  } | kube create -f -
}

secret_fingerprint() {
  kube get secret "$1" -n "$NS" -o jsonpath='{.data.password}' 2>/dev/null |
    shasum -a 256 | awk '{ print substr($1, 1, 16) }'
}

# Operator (if any), then the object that carries Postgres.
apply_operator() {
  local dir
  dir=$(manifest_dir "$1")
  case $1 in
    cnpg) kube apply --server-side -f "$dir/operator.yaml" ;;
    zalando) kube apply -k "$dir/operator" ;;
    statefulset | none) return 0 ;;
  esac
}

apply_postgres() { kube apply -f "$(manifest_dir "$1")/postgres.yaml"; }

delete_postgres() {
  case $1 in
    statefulset) kube delete statefulset postgres -n "$NS" --wait=true ;;
    cnpg) kube delete cluster.postgresql.cnpg.io bench -n "$NS" --wait=true ;;
    zalando) kube delete postgresql.acid.zalan.do acid-bench -n "$NS" --wait=true ;;
  esac
}

# --- Checks from the client pod ---------------------------------------------------

psql_client() {
  kube exec -n "$NS" deploy/pgclient -- psql -X -v ON_ERROR_STOP=1 -tA "$@"
}

db_ready() { [ "$(psql_client -c 'select 1' 2>/dev/null | tr -d '[:space:]')" = 1 ]; }

client_ready() {
  [ "$(kube get deployment pgclient -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = 1 ]
}

write_row() {
  psql_client -c "create table if not exists bench_data (k text primary key, v text not null)" \
    -c "insert into bench_data values ('$1', 'kept') on conflict (k) do update set v = excluded.v"
}

row_kept() {
  [ "$(psql_client -c "select v from bench_data where k = '$1'" 2>/dev/null | tr -d '[:space:]')" = kept ]
}

pod_uid() { kube get pod "$1" -n "$NS" -o jsonpath='{.metadata.uid}' 2>/dev/null || true; }

pods_gone() {
  [ -z "$(kube get pods -n "$NS" -l "$1" -o name 2>/dev/null)" ]
}

postgres_selector() {
  case $1 in
    statefulset) echo "app=postgres" ;;
    cnpg) echo "cnpg.io/cluster=bench" ;;
    zalando) echo "cluster-name=acid-bench" ;;
  esac
}

pvc_count() { kube get pvc -n "$NS" -o name 2>/dev/null | grep -c . || true; }

# --- Cluster ----------------------------------------------------------------------

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
      (.status.desiredNumberScheduled // 0) > 0
      and (.status.numberReady // 0) >= .status.desiredNumberScheduled)'

cluster_ready() {
  local json
  json=$(kube get nodes -o json 2>/dev/null) || return 1
  printf '%s' "$json" | jq -e 'all(.items[]; any(.status.conditions[]?; .type == "Ready" and .status == "True"))' >/dev/null || return 1
  json=$(kube get pods,deployments,daemonsets -n kube-system -o json 2>/dev/null) || return 1
  printf '%s' "$json" | jq -e "$KUBE_SYSTEM_READY" >/dev/null || return 1
  json=$(kube get pods,deployments -n local-path-storage -o json 2>/dev/null) || return 1
  printf '%s' "$json" | jq -e "$KUBE_SYSTEM_READY" >/dev/null
}

cluster_exists() { kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; }

create_cluster() {
  kind create cluster --name "$CLUSTER" --image "$KIND_IMAGE" --kubeconfig "$KUBECONFIG"
}

delete_cluster() { kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG"; }

# --- Records ----------------------------------------------------------------------

record_load() {
  local opt=$1 phase=$2 loadavg total
  loadavg=$(uptime | sed -e 's/.*load average[s]*: //' -e 's/,//g')
  total=$(docker ps -q | wc -l | tr -d ' ')
  tsv load.tsv "$(utc_now)" "$opt" "$phase" "$loadavg" "$total" \
    "$(kind get clusters 2>/dev/null | paste -sd, - || true)"
}

to_mib_awk='function to_mib(v,  n, u) {
  n = v; sub(/[A-Za-z]+$/, "", n); u = v; sub(/^[0-9.]+/, "", u)
  if (u == "B") return n / 1048576
  if (u == "KiB" || u == "kB") return n / 1024
  if (u == "MiB" || u == "MB") return n
  if (u == "GiB" || u == "GB") return n * 1024
  return -1 }'

# One sample: memory working set and CPU of every pod of the layer, from the
# kubelet Summary API, plus the whole node container from docker stats.
# Prints "layer_mem_mib<TAB>layer_cpu_pct<TAB>node_mem_mib<TAB>node_cpu_pct".
idle_sample() {
  local opt=$1 run=$2 sample=$3 summary pods node_stats
  summary=$(kube get --raw "/api/v1/nodes/$NODE/proxy/stats/summary") || die "summary API unreachable"
  pods=$(printf '%s' "$summary" | jq -r --arg nss "$(layer_namespaces "$opt")" '
    ($nss | split(" ")) as $n
    | .pods[] | select(.podRef.namespace as $x | any($n[]; . == $x))
    | select(.podRef.name | startswith("pgclient") | not)
    | [.podRef.namespace, .podRef.name, ((.memory.workingSetBytes // 0) / 1048576),
       ((.cpu.usageNanoCores // 0) / 10000000)] | @tsv')
  printf '%s\n' "$pods" | awk -F'\t' -v o="$opt" -v r="$run" -v s="$sample" \
    'NF == 4 { printf "%s\t%s\t%s\t%s\t%s\t%.1f\t%.2f\n", o, r, s, $1, $2, $3, $4 }' \
    >>"$TRIAL_DIR/idle-pods.tsv"
  node_stats=$(docker stats --no-stream --format '{{.CPUPerc}}\t{{.MemUsage}}' "$NODE" |
    awk -F'\t' "$to_mib_awk"'{ cpu = $1; sub(/%/, "", cpu); split($2, m, " "); printf "%.1f\t%.2f", to_mib(m[1]), cpu }')
  printf '%s\n' "$pods" | awk -F'\t' -v node="$node_stats" \
    'NF == 4 { m += $3; c += $4 } END { printf "%.1f\t%.2f\t%s\n", m, c, node }'
}

# Images the node pulled during the run, from the Pulled events.
record_pulls() {
  local opt=$1 run=$2
  kube get events -A -o json | jq -r '.items[] | select(.reason == "Pulled") | .message' |
    sed -n -e 's/^Successfully pulled image "\([^"]*\)" in \([^ ]*\) .*/pulled|\1|\2/p' \
      -e 's/^Container image "\([^"]*\)" already present.*/present|\1|-/p' |
    sort -u | while IFS='|' read -r status image took; do
      tsv node-images.tsv "$opt" "$run" "$status" "$image" "$took"
    done
}

restarts() {
  local opt=$1 ns total=0 n
  for ns in $(layer_namespaces "$opt"); do
    n=$(kube get pods -n "$ns" -o json | jq '[.items[] | select(.metadata.name | startswith("pgclient") | not) | .status.containerStatuses[]?.restartCount] | add // 0')
    total=$((total + n))
  done
  echo "$total"
}

# Compressed size per architecture (layers plus config) of an image, from the
# registry manifest: no pull, no container.
registry_sizes() {
  docker manifest inspect -v "$1" 2>/dev/null | jq -r '
    [if type == "array" then .[] else . end
     | select((.Descriptor.platform.os // "linux") == "linux")
     | (.SchemaV2Manifest // .OCIManifest) as $m
     | "\(.Descriptor.platform.architecture)=\(([$m.layers[]?.size] | add) + ($m.config.size // 0))"]
    | map(select(startswith("arm64=") or startswith("amd64="))) | join(",")' 2>/dev/null || true
}

record_image() {
  local opt=$1 ref=$2 sizes try repo_tag
  repo_tag=${ref%@*}
  sizes=""
  for try in 1 2; do
    sizes=$(registry_sizes "${repo_tag%:*}@${ref#*@}")
    [ -z "$sizes" ] || break
    log "$opt: no size for $ref (try $try)"
    sleep 5
  done
  tsv images.tsv "$opt" "$ref" "${sizes:--}"
}

# Images the option makes the node pull: the operator and the operand.
option_images() {
  case $1 in
    statefulset) echo "$PG_IMAGE" ;;
    cnpg)
      pin_of "ghcr.io/cloudnative-pg/cloudnative-pg:1.30.2"
      echo "$CNPG_OPERAND"
      ;;
    zalando)
      pin_of "ghcr.io/zalando/postgres-operator:v2.0.3"
      pin_of "ghcr.io/zalando/spilo-18:4.1-p2"
      ;;
  esac
}

record_images() {
  local opt ref
  for opt in $OPTIONS; do
    for ref in $(option_images "$opt"); do record_image "$opt" "$ref"; done
  done
  for ref in $VARIANT_IMAGES; do record_image variant "$ref"; done
}

# --- One run --------------------------------------------------------------------

# --- Power (macOS) ----------------------------------------------------------------

# Rule set after BENCH-012: a run counts only if the Mac stays on AC power,
# lid open, and "pmset -g log" shows no Sleep entry during the run. Reads
# only; skipped where pmset does not exist.
has_pmset() { command -v pmset >/dev/null; }
power_source() { pmset -g ps | sed -n "s/^Now drawing from '\(.*\)'\$/\1/p"; }
battery_pct() { pmset -g ps | grep -Eo '[0-9]+%' | head -n 1; }
lid_closed() { ioreg -r -k AppleClamshellState -d 4 | sed -n -E 's/.*"AppleClamshellState" = (Yes|No).*/\1/p' | head -n 1; }
local_now() { date '+%Y-%m-%d %H:%M:%S'; }

# Sleep entries of "pmset -g log" between two local times (same time zone).
sleep_entries() {
  pmset -g log | awk -v s="$1" -v e="$2" \
    '$4 == "Sleep" { t = $1 " " $2; if (t >= s && t <= e) n++ } END { print n + 0 }'
}

# Refuse to start a run off AC power or with the lid closed.
power_gate() {
  local opt=$1 run=$2 src lid
  RUN_POWER_START=$(local_now)
  has_pmset || return 0
  src=$(power_source)
  lid=$(lid_closed)
  RUN_POWER_STATE="$src $(battery_pct) lid-closed=$lid"
  [ "$src" = "AC Power" ] || die "$opt run $run refused: drawing from '$src', AC power required"
  [ "$lid" = No ] || die "$opt run $run refused: lid closed"
}

# Record the power state over the run and print yes if the run is valid.
power_verdict() {
  local opt=$1 run=$2 end src lid sleeps valid
  end=$(local_now)
  if ! has_pmset; then
    tsv power.tsv "$opt" "$run" "$RUN_POWER_START" "$end" n/a n/a 0 yes
    echo yes
    return 0
  fi
  src=$(power_source)
  lid=$(lid_closed)
  sleeps=$(sleep_entries "$RUN_POWER_START" "$end")
  valid=yes
  if [ "$sleeps" != 0 ] || [ "$src" != "AC Power" ] || [ "$lid" != No ]; then valid=no; fi
  tsv power.tsv "$opt" "$run" "$RUN_POWER_START" "$end" "$RUN_POWER_STATE" \
    "$src $(battery_pct) lid-closed=$lid" "$sleeps" "$valid"
  [ "$valid" = yes ] || log "$opt run $run: INVALID, $sleeps Sleep entries, power '$src', lid closed=$lid"
  echo "$valid"
}

# Node restart (NODE_RESTART=1): a row written and committed just before the
# stop, then "docker stop" and "docker start" of the measurement node only.
# restart.tsv: stop and start durations, then the time until the cluster and
# Postgres are ready again, counted from the end of "docker start".
restart_node() {
  local opt=$1 run=$2 log_file=$3 t0 t_stopped t_started t_cluster_back db_s
  local uid_before uid_after
  write_row "restart-$run" >>"$log_file" 2>&1 || die "$opt run $run: write before restart failed"
  uid_before=$(pod_uid "$(db_pod "$opt")")
  log "$opt run $run: restart the node"
  t0=$(now)
  docker stop "$NODE" >>"$log_file" 2>&1 || die "$opt run $run: docker stop failed"
  t_stopped=$(now)
  docker start "$NODE" >>"$log_file" 2>&1 || die "$opt run $run: docker start failed"
  t_started=$(now)
  kind export kubeconfig --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >>"$log_file" 2>&1 ||
    die "$opt run $run: kubeconfig export failed after restart"
  t_cluster_back=$(wait_streak "$CLUSTER_TIMEOUT" cluster_ready) || die "$opt run $run: cluster not ready after restart"
  data_check "$opt" "$run" node-restarted "$t_started" "restart-$run"
  db_s=-
  if [ -n "$LAST_READY_AT" ]; then db_s=$(seconds_between "$t_started" "$LAST_READY_AT"); fi
  uid_after=$(pod_uid "$(db_pod "$opt")")
  tsv restart.tsv "$opt" "$run" "$(seconds_between "$t0" "$t_stopped")" \
    "$(seconds_between "$t_stopped" "$t_started")" "$(seconds_between "$t_started" "$t_cluster_back")" \
    "$db_s" "$(seconds_between "$t0" "${LAST_READY_AT:-$t_started}")" \
    "$(row_kept "run-$run" && echo yes || echo no)" "$(row_kept "restart-$run" && echo yes || echo no)" \
    "$([ "$uid_before" = "$uid_after" ] && echo same || echo new)" "$(pod_restarts_db "$opt")"
  log "$opt run $run: node restarted, cluster ready after $(seconds_between "$t_started" "$t_cluster_back") s, Postgres after $db_s s"
}

# Restart count of the Postgres container, read after the node restart.
pod_restarts_db() {
  kube get pod "$(db_pod "$1")" -n "$NS" -o json 2>/dev/null |
    jq '[.status.containerStatuses[]?.restartCount] | add // 0'
}

# Wait for "ready", then read back a row: "run-RUN" by default, or the key
# given as fifth argument. The ready time is printed for the caller.
data_check() {
  local opt=$1 run=$2 step=$3 t_start=$4 key=${5:-run-$2} kept ready_s="-" t_ready
  if t_ready=$(wait_streak "$READY_TIMEOUT" db_ready); then
    ready_s=$(seconds_between "$t_start" "$t_ready")
    LAST_READY_AT=$t_ready
  else
    LAST_READY_AT=""
  fi
  if row_kept "$key"; then kept=yes; else kept=no; fi
  tsv data.tsv "$opt" "$run" "$step" "$kept" "$ready_s" "$(pvc_count)" \
    "$(secret_fingerprint "$(db_secret "$opt")")"
  log "$opt run $run: $step, row kept: $kept, ready again after $ready_s s"
}

timed_run() {
  local opt=$1 run=$2 log_file started t_create t_cluster t0 t_ready ready_s
  local samples="" i sample mem cpu node_mem node_cpu version secret_before secret_after uid_before uid_after restarts_at_rest
  log_file="$LOGS/$opt-run-$run.log"
  power_gate "$opt" "$run"
  record_load "$opt" "run-$run"
  started=$(utc_now)
  log "$opt run $run: create cluster"
  t_create=$(now)
  create_cluster >"$log_file" 2>&1 || die "$opt run $run: kind create failed, see $log_file"
  t_cluster=$(wait_streak "$CLUSTER_TIMEOUT" cluster_ready) || die "$opt run $run: cluster not ready"

  if [ "$opt" = none ]; then
    sleep "$IDLE_WAIT"
    for i in $(seq 1 "$SAMPLES"); do
      sample=$(idle_sample "$opt" "$run" "$i")
      samples="$samples$sample"$'\n'
      if [ "$i" -lt "$SAMPLES" ]; then sleep "$SAMPLE_GAP"; fi
    done
    node_mem=$(printf '%s' "$samples" | cut -f3 | grep . | median_range | cut -f1)
    node_cpu=$(printf '%s' "$samples" | cut -f4 | grep . | median_range | cut -f1)
    tsv runs.tsv "$opt" "$run" "$started" "$(seconds_between "$t_create" "$t_cluster")" \
      - - - "$node_mem" "$node_cpu" - - 0 "$(power_verdict "$opt" "$run")"
    log "$opt run $run: node at rest $node_mem MiB"
    delete_cluster >>"$log_file" 2>&1 || die "$opt run $run: delete failed"
    return 0
  fi

  # Storage behind the PVCs: class, provisioner and reclaim policy.
  kube get storageclass -o jsonpath='{range .items[*]}storageclass {.metadata.name} {.provisioner} {.reclaimPolicy}{"\n"}{end}' >>"$log_file" 2>&1 || true
  namespace_manifest | kube apply -f - >>"$log_file" 2>&1
  create_secret "$(db_secret "$opt")" >>"$log_file" 2>&1 || die "$opt run $run: secret creation failed"
  secret_before=$(secret_fingerprint "$(db_secret "$opt")")

  log "$opt run $run: install $(option_version "$opt")"
  t0=$(now)
  apply_operator "$opt" >>"$log_file" 2>&1 || die "$opt run $run: operator apply failed, see $log_file"
  retry apply_postgres "$opt" >>"$log_file" 2>&1 || die "$opt run $run: postgres apply failed, see $log_file"
  kube apply -f "$(manifest_dir "$opt")/client.yaml" >>"$log_file" 2>&1
  if ! t_ready=$(wait_streak "$READY_TIMEOUT" db_ready); then
    kube get pods -A -o wide >>"$log_file" 2>&1 || true
    kube get events -A --field-selector type=Warning >>"$log_file" 2>&1 || true
    die "$opt run $run: not ready after ${READY_TIMEOUT}s, see $log_file"
  fi
  ready_s=$(seconds_between "$t0" "$t_ready")
  log "$opt run $run: ready in $ready_s s"
  version=$(psql_client -c 'show server_version' 2>>"$log_file" | tr -d '\r' | head -n 1)
  secret_after=$(secret_fingerprint "$(db_secret "$opt")")
  write_row "run-$run" >>"$log_file" 2>&1 || die "$opt run $run: write failed"

  # At rest without the client pod.
  kube scale deployment pgclient -n "$NS" --replicas=0 >>"$log_file" 2>&1
  sleep "$IDLE_WAIT"
  for i in $(seq 1 "$SAMPLES"); do
    sample=$(idle_sample "$opt" "$run" "$i")
    samples="$samples$sample"$'\n'
    if [ "$i" -lt "$SAMPLES" ]; then sleep "$SAMPLE_GAP"; fi
  done
  mem=$(printf '%s' "$samples" | cut -f1 | grep . | median_range | cut -f1)
  cpu=$(printf '%s' "$samples" | cut -f2 | grep . | median_range | cut -f1)
  node_mem=$(printf '%s' "$samples" | cut -f3 | grep . | median_range | cut -f1)
  node_cpu=$(printf '%s' "$samples" | cut -f4 | grep . | median_range | cut -f1)
  restarts_at_rest=$(restarts "$opt")
  kube scale deployment pgclient -n "$NS" --replicas=1 >>"$log_file" 2>&1
  wait_streak 120 client_ready >/dev/null || die "$opt run $run: client pod not back"

  # (a) the Postgres pod is deleted.
  uid_before=$(pod_uid "$(db_pod "$opt")")
  t0=$(now)
  kube delete pod "$(db_pod "$opt")" -n "$NS" --wait=false >>"$log_file" 2>&1
  wait_streak 120 sh -c "[ \"\$(kubectl --request-timeout=20s get pod $(db_pod "$opt") -n $NS -o jsonpath='{.metadata.uid}' 2>/dev/null)\" != \"$uid_before\" ]" >/dev/null ||
    log "$opt run $run: pod not recreated within 120 s"
  data_check "$opt" "$run" pod-deleted "$t0"

  # (b) the layer is applied again, as task reload or task up on a kept cluster.
  uid_before=$(pod_uid "$(db_pod "$opt")")
  t0=$(now)
  apply_operator "$opt" >>"$log_file" 2>&1 || die "$opt run $run: operator re-apply failed"
  apply_postgres "$opt" >>"$log_file" 2>&1 || die "$opt run $run: postgres re-apply failed"
  sleep 10
  data_check "$opt" "$run" reapplied "$t0"
  uid_after=$(pod_uid "$(db_pod "$opt")")
  if [ "$uid_before" = "$uid_after" ]; then
    tsv data.tsv "$opt" "$run" reapplied-pod-restarted no - - -
  else
    tsv data.tsv "$opt" "$run" reapplied-pod-restarted yes - - -
  fi

  # (c) the object that carries Postgres is deleted, then applied again.
  t0=$(now)
  delete_postgres "$opt" >>"$log_file" 2>&1 || die "$opt run $run: delete of the postgres object failed"
  wait_streak 180 pods_gone "$(postgres_selector "$opt")" >/dev/null ||
    log "$opt run $run: postgres pods still there after 180 s"
  tsv data.tsv "$opt" "$run" object-deleted-pvc-left - - "$(pvc_count)" \
    "$(secret_fingerprint "$(db_secret "$opt")")"
  retry apply_postgres "$opt" >>"$log_file" 2>&1 || die "$opt run $run: postgres apply after delete failed"
  # A Secret deleted with the object (Zalando) is recreated by the operator:
  # the client pod is restarted to read it again.
  kube rollout restart deployment pgclient -n "$NS" >>"$log_file" 2>&1
  data_check "$opt" "$run" object-recreated "$t0"

  if [ "$NODE_RESTART" = 1 ]; then
    restart_node "$opt" "$run" "$log_file"
  fi

  record_pulls "$opt" "$run"
  tsv runs.tsv "$opt" "$run" "$started" "$(seconds_between "$t_create" "$t_cluster")" \
    "$ready_s" "$mem" "$cpu" "$node_mem" "$node_cpu" "$version" \
    "$([ "$secret_before" = "$secret_after" ] && echo kept || echo changed)" "$restarts_at_rest" \
    "$(power_verdict "$opt" "$run")"
  log "$opt run $run: delete cluster"
  delete_cluster >>"$log_file" 2>&1 || die "$opt run $run: delete failed"
}

# --- Start-up checks --------------------------------------------------------------

check_versions() {
  local v
  for v in docker kind kubectl gh jq shasum awk sed; do
    command -v "$v" >/dev/null || die "$v not found"
  done
  pick_clock
  tsv versions.tsv clock "$CLOCK"
  if has_pmset; then
    tsv versions.tsv power-at-start "$(power_source) $(battery_pct) lid-closed=$(lid_closed)"
    [ "$(power_source)" = "AC Power" ] || die "drawing from '$(power_source)': AC power required (rule after BENCH-012)"
    [ "$(lid_closed)" = No ] || die "lid closed: the Mac must stay open"
  fi
  v=$(kind version | awk '{ print $2 }')
  [ "$v" = "$KIND_VERSION" ] || die "kind $v found, $KIND_VERSION expected"
  tsv versions.tsv kind "$v"
  v=$(kubectl version --client -o json | jq -r '.clientVersion.minor' | tr -dc '0-9')
  case " $KUBECTL_MINORS " in
    *" $v "*) ;;
    *) die "kubectl 1.$v is more than one minor away from the node image" ;;
  esac
  tsv versions.tsv kubectl "$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion')"
  tsv versions.tsv node-image "$KIND_IMAGE"
  tsv versions.tsv docker "$(docker version --format '{{.Server.Version}}')"
  tsv versions.tsv engine "$(docker info --format '{{.OperatingSystem}} {{.Architecture}} {{.NCPU}} CPU {{.MemTotal}} B cgroup v{{.CgroupVersion}}')"
  tsv versions.tsv host "$(sysctl -n hw.model 2>/dev/null || uname -m) $(sw_vers -productVersion 2>/dev/null || uname -r)"
  for v in $OPTIONS; do
    case $v in
      statefulset | cnpg | zalando | none) tsv versions.tsv "$v" "$(option_version "$v")" ;;
      *) die "unknown option: $v" ;;
    esac
  done
  case $NODE_RESTART in
    0 | 1) tsv versions.tsv node-restart "$NODE_RESTART" ;;
    *) die "NODE_RESTART must be 0 or 1" ;;
  esac
}

acquire_lock() {
  [ -n "$BENCH_LOCK" ] || return 0
  if ! mkdir "$BENCH_LOCK" 2>/dev/null; then
    echo "lock $BENCH_LOCK is held: $(cat "$BENCH_LOCK/owner" 2>/dev/null || echo unknown owner)" >&2
    exit 75
  fi
  LOCK_HELD=1
  printf 'BENCH-011 %s\n' "$(utc_now)" >"$BENCH_LOCK/owner"
}

release_lock() {
  if [ "$LOCK_HELD" = 1 ]; then
    rm -f "$BENCH_LOCK/owner"
    rmdir "$BENCH_LOCK" 2>/dev/null || log "lock $BENCH_LOCK not empty, left in place"
    LOCK_HELD=0
  fi
}

# --- Cleanup ----------------------------------------------------------------------

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  set +e
  if cluster_exists; then
    log "cleanup: deleting the kind cluster $CLUSTER"
    delete_cluster >>"$LOGS/cleanup.log" 2>&1
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

# --- Summary ----------------------------------------------------------------------

# Runs marked invalid in power.tsv (Sleep entry, battery, lid) are left out.
summary_line() {
  local opt=$1 name=$2 values=$3
  tsv summary.tsv "$opt" "$name" "$(printf '%s\n' "$values" | grep -c . || true)" \
    "$(printf '%s\n' "$values" | paste -sd, -)" "$(printf '%s\n' "$values" | grep . | median_range)"
}

summarize() {
  local opt column name values invalid
  invalid=$(awk -F'\t' '$NF == "no" { printf "%s:%s ", $1, $2 }' "$TRIAL_DIR/power.tsv")
  tsv summary.tsv option metric runs values median range
  for opt in $OPTIONS; do
    for column in 4:cluster_s 5:ready_s 6:layer_mem_mib 7:layer_cpu_pct 8:node_mem_mib 9:node_cpu_pct; do
      name=${column#*:}
      values=$(awk -F'\t' -v o="$opt" -v c="${column%%:*}" -v bad="$invalid" \
        '$1 == o && $2 != "run" && index(bad, $1 ":" $2 " ") == 0 && $c ~ /^[0-9.]+$/ { print $c }' "$TRIAL_DIR/runs.tsv")
      summary_line "$opt" "$name" "$values"
    done
    values=$(awk -F'\t' -v o="$opt" -v bad="$invalid" \
      '$1 == o && $3 == "pod-deleted" && index(bad, $1 ":" $2 " ") == 0 && $5 ~ /^[0-9.]+$/ { print $5 }' "$TRIAL_DIR/data.tsv")
    summary_line "$opt" pod_back_s "$values"
    for column in 5:restart_cluster_s 6:restart_db_s 7:restart_total_s; do
      values=$(awk -F'\t' -v o="$opt" -v c="${column%%:*}" -v bad="$invalid" \
        '$1 == o && $2 != "run" && index(bad, $1 ":" $2 " ") == 0 && $c ~ /^[0-9.]+$/ { print $c }' "$TRIAL_DIR/restart.tsv")
      [ -z "$values" ] || summary_line "$opt" "${column#*:}" "$values"
    done
  done
  [ -z "$invalid" ] || log "runs left out of the summary (power): $invalid"
}

# --- Main -------------------------------------------------------------------------

main() {
  local opt run
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
  mkdir -p "$LOGS"
  export KUBECONFIG="$TRIAL_DIR/kubeconfig"
  : >"$KUBECONFIG"
  chmod 600 "$KUBECONFIG"

  tsv versions.tsv item version
  tsv manifests.tsv option version file sha256
  tsv images.tsv option image compressed_bytes
  tsv runs.tsv option run started_utc cluster_s ready_s layer_mem_mib layer_cpu_pct \
    node_mem_mib node_cpu_pct server_version secret restarts power_valid
  tsv idle-pods.tsv option run sample namespace pod mem_mib cpu_pct
  tsv node-images.tsv option run status image took
  tsv data.tsv option run step row_kept ready_again_s pvcs secret_sha256_16
  tsv restart.tsv option run stop_s start_s cluster_ready_s db_ready_s total_s \
    row_run_kept row_restart_kept db_pod db_restarts
  tsv power.tsv option run start_local end_local power_start power_end sleep_entries valid
  tsv load.tsv utc option phase loadavg_1_5_15 running_containers kind_clusters

  # Start-up checks first, without any trap: a refusal deletes nothing.
  check_versions
  cluster_exists && die "a kind cluster named $CLUSTER already exists"
  if docker network inspect kind >/dev/null 2>&1; then KIND_NETWORK_EXISTED=1; fi
  acquire_lock
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  log "trial directory: $TRIAL_DIR"

  for opt in $OPTIONS; do
    case $opt in
      cnpg) fetch_cnpg ;;
      zalando) fetch_zalando ;;
    esac
    [ "$opt" = none ] || write_layer "$opt"
  done
  record_images

  run=1
  while [ "$run" -le "$RUNS" ]; do
    for opt in $OPTIONS; do
      timed_run "$opt" "$run"
      sleep "$PAUSE_BETWEEN_RUNS"
    done
    run=$((run + 1))
  done
  summarize
  column -t -s "$(printf '\t')" "$TRIAL_DIR/summary.tsv" >&2 || true
}

main "$@"
