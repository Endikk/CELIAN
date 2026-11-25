#!/usr/bin/env bash
# BENCH-014: cache engine of the generated project, in the local kind cluster.
# Options:
#   valkey  the valkey/valkey image (Valkey 9.1.4, the minor line that
#           Memorystore for Valkey serves by default), one Deployment and one
#           Service written by hand, no persistence;
#   redis   the official redis image (Redis 7.2.17, the minor line that
#           Memorystore for Redis serves by default, BSD-3-Clause), same
#           manifests;
#   none    the base node: kind alone, same image and configuration
#           (memory baseline of M2, measured in the same series).
# Both engines get the same manifests: an init container writes the server
# configuration (no snapshot, no AOF, requirepass) into an in-memory volume,
# reading the password from the mounted Secret "cache-auth"; the server reads
# that file, so the password is never in a command line, an argument or an
# environment variable of the server.
# Each run creates a fresh kind cluster (kind 0.33.0, node image pinned by
# digest, as in ADR-004) and measures, for one option:
#   - M1, installation until "ready": from the first kubectl apply of the
#     layer to the first of three successful authenticated PING (reply PONG)
#     through the Service "cache", run with kubectl exec in a client pod of
#     the cluster, one try per second;
#   - M2, M3, memory and CPU at rest, IDLE_WAIT seconds after "ready", client
#     scaled to zero: the node container from docker stats, the layer's pods
#     from the kubelet Summary API (3 samples, 10 s apart);
#   - M5, the images the node pulled (Pulled events);
#   - M6, authentication: PING without password refused, SET then GET with
#     password, password absent from every command line of the cache pod;
#   - M7, back to "ready" after the cache pod is deleted;
#   - M8, the version served (INFO server).
# M4 (compressed size per architecture) is read at the registry, no pull.
# Runs are interleaved (option A, option B, ..., then the next run).
# On macOS, the script starts, and each run starts, only on AC power with the
# lid open; a run during which "pmset -g log" shows a Sleep entry, or that
# ends off AC power or lid closed, is marked invalid (power.tsv) and left out
# of the summary (rule set after BENCH-012, check taken from BENCH-011).
# While it runs, the script holds "caffeinate -i -s" (no idle sleep, no
# system sleep on AC power); closing the lid still puts the Mac to sleep.
#
# Usage: tests/bench/bench-014-cache.sh [TRIAL_DIR]
#   TRIAL_DIR, if given, must be missing or empty (default: a new mktemp -d).
#   Environment:
#     OPTIONS="none valkey redis"  options, interleaved in order
#     RUNS=3            runs per option
#     IDLE_WAIT=120     seconds between "ready" and the first sample
#     BENCH_LOCK=DIR    optional lock directory shared with other benchmarks:
#                       created with mkdir right after the start-up checks
#                       (exit code 75 if it exists), holds an "owner" file,
#                       removed by the EXIT trap
#   Results (TSV) in TRIAL_DIR: versions.tsv, images.tsv, runs.tsv,
#   idle-pods.tsv, node-images.tsv, auth.tsv, pod-restart.tsv, power.tsv,
#   load.tsv, summary.tsv; command output in TRIAL_DIR/logs/.
# Needs: bash >= 3.2, docker (with buildx), kind v0.33.0, kubectl (1.35 to
#   1.37), jq, shasum, awk. gdate (GNU coreutils) is used for the clock when
#   present; without it the clock falls back to `date +%s` (1 s resolution),
#   recorded in versions.tsv. On macOS, pmset and ioreg for the power checks.
#
# Safety:
#   - the cluster is named celian-bench-014. The script refuses to start if it
#     already exists. Its EXIT trap is set only after the start-up checks, so a
#     refusal deletes nothing; afterwards it deletes only that cluster;
#   - umask 077; KUBECONFIG points into TRIAL_DIR: ~/.kube is neither read nor
#     written;
#   - no port is published to the host: kind keeps its API on 127.0.0.1 and
#     every check runs from a pod inside the cluster;
#   - the cache password is drawn from /dev/urandom and piped to
#     kubectl create -f -: never in a file, a variable or an argument on the
#     host. Nothing derived from it (no hash, no prefix) is written to
#     TRIAL_DIR;
#   - nothing is built and no image is removed: the node pulls every image;
#   - no curl, wget, python, node or perl.
# Side effects outside TRIAL_DIR: the "kind" Docker network, removed at the
#   end if the script created it and nothing uses it. The node pulls the
#   images from docker.io at every run.
# Commands that create, change or remove a container or a network, for the
# [SECU] review before the first run:
#   kind create cluster      (create_cluster) starts the node with
#                            "docker run --privileged", creates the "kind"
#                            network if missing
#   kind delete cluster      (delete_cluster, cleanup) removes the node
#   docker network rm kind   (cleanup) only if this run created it and it
#                            is empty
# No docker run, start, stop, restart, exec, cp or create in this script.
# Pods are created and deleted only inside the kind node, by kubectl.
# Every other docker call only reads: ps, stats, manifest inspect,
# buildx imagetools inspect, network inspect, version, info.
# Power checks only read: pmset -g ps, pmset -g log, ioreg -r -k
# AppleClamshellState. caffeinate -i -s -w <script pid> holds a sleep
# assertion, released when the script exits.
set -euo pipefail
umask 077

# --- Pinned versions ----------------------------------------------------------

readonly KIND_VERSION="v0.33.0"
readonly KIND_IMAGE="kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed"
readonly KUBECTL_MINORS="35 36 37"

# Option valkey: tag 9.1.4-alpine, index digest read on 2026-11-23 from the
# Docker Hub API; the same digest is pinned in bench-005-orchestration.sh.
readonly VALKEY_IMAGE="docker.io/valkey/valkey:9.1.4-alpine@sha256:56729e68bdda139cbd3f6a2538683dc3523325fc5711ea1a379938f1b37893f0"
# Option redis: tag 7.2.17-alpine, index digest read on 2026-11-23 in
# docker-library/repo-info (repos/redis/remote/7.2.17-alpine.md).
readonly REDIS_IMAGE="docker.io/library/redis:7.2.17-alpine@sha256:2f66de68111e64c3927859f158f8e666066dae2b97d9f82770a6f37a5aa1c335"

# Debian variants, read at the registry for the sensitivity analysis, never
# pulled. Digests read on 2026-11-23 (Docker Hub API, repo-info).
readonly VARIANT_IMAGES="
docker.io/valkey/valkey:9.1.4-trixie@sha256:3ab0eca823ebbf0fe352476ebac330ac9e5f14b592b9a954eab296d341e81b0e
docker.io/library/redis:7.2.17-bookworm@sha256:5b816bb37d9707a70f10ef5002ecf8ee431750d397010fc4314c93dca887962f
"

readonly CLUSTER="celian-bench-014"
readonly NODE="$CLUSTER-control-plane"
readonly NS="bench-cache"
readonly SECRET="cache-auth"
readonly SAMPLES=3
readonly SAMPLE_GAP=10
readonly PAUSE_BETWEEN_RUNS=15
readonly READY_STREAK=3
readonly CLUSTER_TIMEOUT=300
readonly READY_TIMEOUT=600
readonly BACK_TIMEOUT=180

OPTIONS="${OPTIONS:-none valkey redis}"
RUNS="${RUNS:-3}"
IDLE_WAIT="${IDLE_WAIT:-120}"
BENCH_LOCK="${BENCH_LOCK:-}"
readonly OPTIONS RUNS IDLE_WAIT BENCH_LOCK

TRIAL_DIR=""
LOGS=""
LOCK_HELD=0
KIND_NETWORK_EXISTED=0
CLI=""
OLD_POD=""
RUN_POWER_START=""
RUN_POWER_STATE="n/a"
CURRENT_RUN=""

# --- Helpers ------------------------------------------------------------------

log() { printf '[bench-014 %s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die() {
  log "ERROR: $*"
  exit 1
}

if command -v gdate >/dev/null 2>&1; then
  readonly CLOCK="gdate"
  now() { gdate +%s.%N; }
else
  readonly CLOCK="date (1 s)"
  now() { date +%s; }
fi

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

# --- Options ------------------------------------------------------------------

option_image() {
  case $1 in
    valkey) echo "$VALKEY_IMAGE" ;;
    redis) echo "$REDIS_IMAGE" ;;
  esac
}

option_server() {
  case $1 in
    valkey) echo "valkey-server" ;;
    redis) echo "redis-server" ;;
  esac
}

option_cli() {
  case $1 in
    valkey) echo "valkey-cli" ;;
    redis) echo "redis-cli" ;;
  esac
}

option_version() {
  case $1 in
    valkey) echo "valkey 9.1.4-alpine" ;;
    redis) echo "redis 7.2.17-alpine" ;;
    none) echo "-" ;;
  esac
}

# UID and GID of the server user in both alpine images (Dockerfiles of
# valkey-io/valkey-container 9.1/alpine and redis/docker-library-redis
# v7.2.17 alpine: adduser -u 999, addgroup -g 1000).
readonly RUN_UID=999
readonly RUN_GID=1000

# --- Manifests ------------------------------------------------------------------

manifest_dir() { echo "$TRIAL_DIR/manifests/$1"; }

namespace_manifest() {
  cat <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $NS
  labels:
    pod-security.kubernetes.io/enforce: restricted
EOF
}

# Pod and container security settings shared by the cache and the client:
# profile "restricted" of the Pod Security Standards.
pod_security() {
  cat <<EOF
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: $RUN_UID
        runAsGroup: $RUN_GID
        fsGroup: $RUN_GID
        seccompProfile: {type: RuntimeDefault}
EOF
}

container_security() {
  cat <<EOF
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: {drop: [ALL]}
EOF
}

# The init container writes the configuration from the Secret file: the
# password goes from the file to the configuration through cat and a
# redirection, never through an argument. The server reads the file.
cache_manifest() {
  local opt=$1 image server
  image=$(option_image "$opt")
  server=$(option_server "$opt")
  cat <<EOF
apiVersion: v1
kind: Service
metadata:
  name: cache
  namespace: $NS
spec:
  selector: {app: cache}
  ports: [{port: 6379, targetPort: 6379}]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cache
  namespace: $NS
spec:
  replicas: 1
  selector:
    matchLabels: {app: cache}
  template:
    metadata:
      labels: {app: cache}
    spec:
$(pod_security)
      initContainers:
        - name: config
          image: $image
          command:
            - sh
            - -c
            - |
              umask 077
              {
                printf '%s\n' 'save ""' 'appendonly no' 'protected-mode yes'
                printf 'requirepass '
                cat /run/secrets/cache/password
                printf '\n'
              } > /etc/cache/cache.conf
$(container_security)
          volumeMounts:
            - {name: config, mountPath: /etc/cache}
            - {name: auth, mountPath: /run/secrets/cache, readOnly: true}
      containers:
        - name: cache
          image: $image
          args: [$server, /etc/cache/cache.conf]
          ports: [{containerPort: 6379}]
          readinessProbe:
            tcpSocket: {port: 6379}
            periodSeconds: 2
$(container_security)
          volumeMounts:
            - {name: config, mountPath: /etc/cache, readOnly: true}
            - {name: auth, mountPath: /run/secrets/cache, readOnly: true}
            - {name: data, mountPath: /data}
      volumes:
        - name: config
          emptyDir: {medium: Memory, sizeLimit: 1Mi}
        - name: data
          emptyDir: {}
        - name: auth
          secret: {secretName: $SECRET, defaultMode: 0440}
EOF
}

# Client pod: the option's own image, already pulled by the node, so that the
# client adds no download. The CLI reads the password from REDISCLI_AUTH
# (redis-cli; valkey-cli falls back to it), never from an argument.
client_manifest() {
  local opt=$1
  cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cacheclient
  namespace: $NS
spec:
  replicas: 1
  selector:
    matchLabels: {app: cacheclient}
  template:
    metadata:
      labels: {app: cacheclient}
    spec:
$(pod_security)
      terminationGracePeriodSeconds: 1
      containers:
        - name: cacheclient
          image: $(option_image "$opt")
          command: [sh, -c, "trap 'exit 0' TERM; while :; do sleep 1; done"]
          env:
            - {name: REDISCLI_AUTH, valueFrom: {secretKeyRef: {name: $SECRET, key: password}}}
$(container_security)
EOF
}

write_layer() {
  local opt=$1 dir
  dir=$(manifest_dir "$opt")
  mkdir -p "$dir"
  cache_manifest "$opt" >"$dir/cache.yaml"
  client_manifest "$opt" >"$dir/client.yaml"
  if grep -E '^[[:space:]]*(-[[:space:]]+)?image:' "$dir/cache.yaml" "$dir/client.yaml" | grep -v '@sha256:' >/dev/null; then
    die "$opt: an image without a pinned digest"
  fi
}

# The password never leaves a pipe: /dev/urandom, then kubectl create -f -.
create_secret() {
  {
    printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: %s\n  namespace: %s\n' "$SECRET" "$NS"
    printf 'type: Opaque\nstringData:\n  password: '
    LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 40
    printf '\n'
  } | kube create -f -
}

# --- Checks from the client pod ---------------------------------------------------

cli_client() { kube exec -n "$NS" deploy/cacheclient -- "$CLI" -h cache -p 6379 "$@"; }

cache_ready() { [ "$(cli_client ping 2>/dev/null | tr -d '[:space:]')" = PONG ]; }

client_ready() {
  [ "$(kube get deployment cacheclient -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = 1 ]
}

cache_pod() {
  kube get pods -n "$NS" -l app=cache -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

# Ready again with a new pod: the deleted one is gone and PING answers.
cache_back() {
  ! kube get pod "$OLD_POD" -n "$NS" >/dev/null 2>&1 && cache_ready
}

# M6 (a): PING without password, through the Service.
noauth_refused() {
  kube exec -n "$NS" deploy/cacheclient -- sh -c \
    "unset REDISCLI_AUTH VALKEYCLI_AUTH; exec $CLI -h cache -p 6379 ping" 2>&1 |
    grep -q NOAUTH
}

# M6 (c): number of command lines of the cache pod that contain the
# password, counted inside the pod with the Secret file as the pattern.
password_in_cmdlines() {
  # shellcheck disable=SC2016 # expanded by the shell of the pod
  kube exec -n "$NS" deploy/cache -c cache -- sh -c '
    [ -s /run/secrets/cache/password ] || { echo err; exit 0; }
    cat /proc/[0-9]*/cmdline 2>/dev/null | tr "\000" "\n" |
      grep -c -F -f /run/secrets/cache/password || true' 2>/dev/null | tr -d '[:space:]' || true
}

server_info() {
  local info name version
  info=$(cli_client info server 2>/dev/null | tr -d '\r' || true)
  name=$(printf '%s\n' "$info" | sed -n 's/^server_name://p' | head -n 1)
  version=$(printf '%s\n' "$info" | sed -n 's/^valkey_version://p' | head -n 1)
  if [ -z "$version" ]; then
    version=$(printf '%s\n' "$info" | sed -n 's/^redis_version://p' | head -n 1)
  fi
  printf '%s\t%s\n' "${name:-redis}" "${version:--}"
}

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
  pods=$(printf '%s' "$summary" | jq -r --arg ns "$NS" '
    .pods[] | select(.podRef.namespace == $ns)
    | select(.podRef.name | startswith("cacheclient") | not)
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

idle_samples() {
  local opt=$1 run=$2 i samples=""
  sleep "$IDLE_WAIT"
  for i in $(seq 1 "$SAMPLES"); do
    samples="$samples$(idle_sample "$opt" "$run" "$i")"$'\n'
    if [ "$i" -lt "$SAMPLES" ]; then sleep "$SAMPLE_GAP"; fi
  done
  printf '%s' "$samples"
}

column_median() { cut -f"$1" | grep . | median_range | cut -f1; }

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
  kube get pods -n "$NS" -o json |
    jq '[.items[] | select(.metadata.name | startswith("cacheclient") | not) | .status.containerStatuses[]?.restartCount] | add // 0'
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

repo_at_digest() {
  local ref=$1 repo_tag
  repo_tag=${ref%@*}
  echo "${repo_tag%:*}@${ref#*@}"
}

record_image() {
  local opt=$1 ref=$2 sizes try
  sizes=""
  for try in 1 2; do
    sizes=$(registry_sizes "$(repo_at_digest "$ref")")
    [ -z "$sizes" ] || break
    log "$opt: no size for $ref (try $try)"
    sleep 5
  done
  tsv images.tsv "$opt" "$ref" "${sizes:--}"
}

record_images() {
  local opt ref
  for opt in $OPTIONS; do
    [ "$opt" = none ] || record_image "$opt" "$(option_image "$opt")"
  done
  for ref in $VARIANT_IMAGES; do record_image variant "$ref"; done
}

# --- Power (macOS) ----------------------------------------------------------------

# Rule set after BENCH-012: a run counts only if the Mac stays on AC power,
# lid open, and "pmset -g log" shows no Sleep entry during the run. Reads
# only; skipped where pmset does not exist. Taken from bench-011-postgres.sh
# (branch docs/bench-011-node-restart).
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
  CURRENT_RUN="$opt $run"
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

# --- One run --------------------------------------------------------------------

timed_run() {
  local opt=$1 run=$2 log_file started t_create t_cluster t0 t_ready ready_s
  local samples mem cpu node_mem node_cpu info refused set_get count back_s key_after rest_restarts
  log_file="$LOGS/$opt-run-$run.log"
  power_gate "$opt" "$run"
  record_load "$opt" "run-$run"
  started=$(utc_now)
  log "$opt run $run: create cluster"
  t_create=$(now)
  create_cluster >"$log_file" 2>&1 || die "$opt run $run: kind create failed, see $log_file"
  t_cluster=$(wait_streak "$CLUSTER_TIMEOUT" cluster_ready) || die "$opt run $run: cluster not ready"

  if [ "$opt" = none ]; then
    samples=$(idle_samples "$opt" "$run")
    node_mem=$(printf '%s\n' "$samples" | column_median 3)
    node_cpu=$(printf '%s\n' "$samples" | column_median 4)
    log "$opt run $run: node at rest $node_mem MiB"
    delete_cluster >>"$log_file" 2>&1 || die "$opt run $run: delete failed"
    tsv runs.tsv "$opt" "$run" "$started" "$(seconds_between "$t_create" "$t_cluster")" \
      - - - "$node_mem" "$node_cpu" - - 0 "$(power_verdict "$opt" "$run")"
    CURRENT_RUN=""
    return 0
  fi

  CLI=$(option_cli "$opt")
  namespace_manifest | kube apply -f - >>"$log_file" 2>&1
  create_secret >>"$log_file" 2>&1 || die "$opt run $run: secret creation failed"

  log "$opt run $run: install $(option_version "$opt")"
  t0=$(now)
  kube apply -f "$(manifest_dir "$opt")/cache.yaml" >>"$log_file" 2>&1 || die "$opt run $run: cache apply failed, see $log_file"
  kube apply -f "$(manifest_dir "$opt")/client.yaml" >>"$log_file" 2>&1 || die "$opt run $run: client apply failed, see $log_file"
  if ! t_ready=$(wait_streak "$READY_TIMEOUT" cache_ready); then
    kube get pods -A -o wide >>"$log_file" 2>&1 || true
    kube get events -A --field-selector type=Warning >>"$log_file" 2>&1 || true
    die "$opt run $run: not ready after ${READY_TIMEOUT}s, see $log_file"
  fi
  ready_s=$(seconds_between "$t0" "$t_ready")
  log "$opt run $run: ready in $ready_s s"
  info=$(server_info)

  # M6: authentication.
  if noauth_refused; then refused=yes; else refused=no; fi
  if cli_client set bench-key kept >>"$log_file" 2>&1 &&
    [ "$(cli_client get bench-key 2>/dev/null | tr -d '[:space:]')" = kept ]; then
    set_get=yes
  else
    set_get=no
  fi
  count=$(password_in_cmdlines)
  tsv auth.tsv "$opt" "$run" "$refused" "$set_get" "${count:-err}"
  log "$opt run $run: no-auth refused $refused, set/get $set_get, password in command lines ${count:-err}"

  # At rest without the client pod.
  kube scale deployment cacheclient -n "$NS" --replicas=0 >>"$log_file" 2>&1
  samples=$(idle_samples "$opt" "$run")
  mem=$(printf '%s\n' "$samples" | column_median 1)
  cpu=$(printf '%s\n' "$samples" | column_median 2)
  node_mem=$(printf '%s\n' "$samples" | column_median 3)
  node_cpu=$(printf '%s\n' "$samples" | column_median 4)
  rest_restarts=$(restarts)
  kube scale deployment cacheclient -n "$NS" --replicas=1 >>"$log_file" 2>&1
  wait_streak 120 client_ready >/dev/null || die "$opt run $run: client pod not back"

  # M7: the cache pod is deleted; the Deployment starts a new one.
  OLD_POD=$(cache_pod)
  [ -n "$OLD_POD" ] || die "$opt run $run: no cache pod"
  back_s="-"
  t0=$(now)
  kube delete pod "$OLD_POD" -n "$NS" --wait=false >>"$log_file" 2>&1
  if t_ready=$(wait_streak "$BACK_TIMEOUT" cache_back); then
    back_s=$(seconds_between "$t0" "$t_ready")
  fi
  if [ "$(cli_client get bench-key 2>/dev/null | tr -d '[:space:]')" = kept ]; then
    key_after=yes
  else
    key_after=no
  fi
  tsv pod-restart.tsv "$opt" "$run" "$back_s" "$key_after"
  log "$opt run $run: back after $back_s s, key kept: $key_after"

  record_pulls "$opt" "$run"
  log "$opt run $run: delete cluster"
  delete_cluster >>"$log_file" 2>&1 || die "$opt run $run: delete failed"
  tsv runs.tsv "$opt" "$run" "$started" "$(seconds_between "$t_create" "$t_cluster")" \
    "$ready_s" "$mem" "$cpu" "$node_mem" "$node_cpu" "$info" "$rest_restarts" \
    "$(power_verdict "$opt" "$run")"
  CURRENT_RUN=""
}

# --- Start-up checks --------------------------------------------------------------

# The pinned digest must exist at the registry (a typo stops the script
# before any cluster). A tag that moved since the pin is only recorded.
check_pin() {
  local ref=$1 repo_tag resolved
  repo_tag=${ref%@*}
  docker manifest inspect "$(repo_at_digest "$ref")" >/dev/null 2>&1 ||
    die "pinned digest not found at the registry: $ref"
  resolved=$(docker buildx imagetools inspect "$repo_tag" --format '{{json .Manifest}}' 2>/dev/null |
    jq -r '.digest // empty' 2>/dev/null || true)
  if [ "$resolved" = "${ref#*@}" ]; then
    tsv versions.tsv image "$ref" tag-matches
  else
    tsv versions.tsv image "$ref" "tag-now:${resolved:-unknown}"
    log "warning: $repo_tag now resolves to ${resolved:-nothing}, the pinned digest is used"
  fi
}

check_versions() {
  local v
  for v in docker kind kubectl jq shasum awk; do
    command -v "$v" >/dev/null || die "$v not found"
  done
  v=$(kind version | awk '{ print $2 }')
  [ "$v" = "$KIND_VERSION" ] || die "kind $v found, $KIND_VERSION expected"
  tsv versions.tsv kind "$v" -
  v=$(kubectl version --client -o json | jq -r '.clientVersion.minor' | tr -dc '0-9')
  case " $KUBECTL_MINORS " in
    *" $v "*) ;;
    *) die "kubectl 1.$v is more than one minor away from the node image" ;;
  esac
  tsv versions.tsv kubectl "$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion')" -
  tsv versions.tsv node-image "$KIND_IMAGE" -
  tsv versions.tsv docker "$(docker version --format '{{.Server.Version}}')" -
  tsv versions.tsv engine "$(docker info --format '{{.OperatingSystem}} {{.Architecture}} {{.NCPU}} CPU {{.MemTotal}} B cgroup v{{.CgroupVersion}}')" -
  tsv versions.tsv host "$(sysctl -n hw.model 2>/dev/null || uname -m) $(sw_vers -productVersion 2>/dev/null || uname -r)" -
  tsv versions.tsv clock "$CLOCK" -
  if has_pmset; then
    tsv versions.tsv power-at-start "$(power_source) $(battery_pct) lid-closed=$(lid_closed)" -
    [ "$(power_source)" = "AC Power" ] || die "drawing from '$(power_source)': AC power required (rule after BENCH-012)"
    [ "$(lid_closed)" = No ] || die "lid closed: the Mac must stay open"
  fi
  for v in $OPTIONS; do
    case $v in
      valkey | redis | none) tsv versions.tsv "$v" "$(option_version "$v")" - ;;
      *) die "unknown option: $v" ;;
    esac
  done
  for v in $OPTIONS; do
    [ "$v" = none ] || check_pin "$(option_image "$v")"
  done
}

acquire_lock() {
  [ -n "$BENCH_LOCK" ] || return 0
  if ! mkdir "$BENCH_LOCK" 2>/dev/null; then
    echo "lock $BENCH_LOCK is held: $(cat "$BENCH_LOCK/owner" 2>/dev/null || echo unknown owner)" >&2
    exit 75
  fi
  LOCK_HELD=1
  printf 'BENCH-014 %s\n' "$(utc_now)" >"$BENCH_LOCK/owner"
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
  if [ -n "$CURRENT_RUN" ]; then
    # shellcheck disable=SC2086 # "option run", split on purpose
    log "cleanup: run $CURRENT_RUN did not finish, power state recorded: $(power_verdict $CURRENT_RUN)"
  fi
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
      '$1 == o && index(bad, $1 ":" $2 " ") == 0 && $3 ~ /^[0-9.]+$/ { print $3 }' "$TRIAL_DIR/pod-restart.tsv")
    summary_line "$opt" pod_back_s "$values"
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
  TRIAL_DIR=$(cd "$TRIAL_DIR" && pwd)
  LOGS="$TRIAL_DIR/logs"
  mkdir -p "$LOGS"
  export KUBECONFIG="$TRIAL_DIR/kubeconfig"
  : >"$KUBECONFIG"
  chmod 600 "$KUBECONFIG"

  tsv versions.tsv item version check
  tsv images.tsv option image compressed_bytes
  tsv runs.tsv option run started_utc cluster_s ready_s layer_mem_mib layer_cpu_pct \
    node_mem_mib node_cpu_pct server_name server_version restarts power_valid
  tsv power.tsv option run start_local end_local power_start power_end sleep_entries valid
  tsv idle-pods.tsv option run sample namespace pod mem_mib cpu_pct
  tsv node-images.tsv option run status image took
  tsv auth.tsv option run noauth_refused set_get_ok password_in_cmdlines
  tsv pod-restart.tsv option run back_s key_kept
  tsv load.tsv utc option phase loadavg_1_5_15 running_containers kind_clusters

  # Start-up checks first, without any trap: a refusal deletes nothing.
  check_versions
  cluster_exists && die "a kind cluster named $CLUSTER already exists"
  if docker network inspect kind >/dev/null 2>&1; then KIND_NETWORK_EXISTED=1; fi
  acquire_lock
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  if command -v caffeinate >/dev/null; then
    caffeinate -i -s -w $$ &
    tsv versions.tsv keep-awake "caffeinate -i -s" -
  fi
  log "trial directory: $TRIAL_DIR"

  for opt in $OPTIONS; do
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
