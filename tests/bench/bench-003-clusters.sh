#!/usr/bin/env bash
# BENCH-003: local Kubernetes cluster for the generated project, on the PC.
# Options: k3d, kind, minikube (Docker driver), all on the same Kubernetes
# version. For each option the script measures:
#   - creation time until "ready": every node Ready, and every kube-system
#     pod Ready (or Succeeded), with Deployments, DaemonSets and Jobs done;
#   - CPU and memory of the cluster containers at rest, IDLE_WAIT seconds
#     after "ready", with `docker stats --no-stream` (3 samples, 10 s apart);
#   - deletion time, until no container of the cluster is left.
# Then, once per option, functional checks useful to the blueprint: port
# published to the host, local image loaded without a registry, local
# registry, Gateway API CRDs, multi-node cluster, and the address the API
# server and the published ports listen on.
#
# Usage: tests/bench/bench-003-clusters.sh [TRIAL_DIR]
#   TRIAL_DIR, if given, must be missing or empty (default: a new mktemp -d).
#   Environment:
#     OPTIONS="k3d kind minikube"  options, measured in this order
#     RUNS=3        runs per option, after the cold run
#     COLD=1        add a first run per option without its pinned images
#                   (removed by exact reference beforehand); 0 to skip it
#     FUNCTIONAL=1  run the functional checks after the timings; 0 to skip
#     IDLE_WAIT=120 seconds between "ready" and the first idle sample
#   Results (TSV) in TRIAL_DIR: versions.tsv, load.tsv, runs.tsv,
#   idle-samples.tsv, ports.tsv, images.tsv, node-images.tsv, functional.tsv,
#   leftovers.tsv, summary.tsv; command output in TRIAL_DIR/logs/.
# Needs: bash >= 3.2, docker, kubectl (1.35 to 1.37), jq, perl, nc, lsof,
#   shasum, and the options measured: k3d, kind, minikube at the versions
#   pinned below. The Gateway API check also needs gh; without it, or if the
#   downloaded file does not match its pinned SHA-256, the check is skipped.
#
# Safety:
#   - every cluster is named celian-bench-003. The script refuses to start if
#     a container of that cluster already exists. Its EXIT trap is set only
#     after the start-up checks, so a refusal deletes nothing; afterwards it
#     deletes only that name, with each tool's own delete command;
#   - umask 077: the trial directory, the kubeconfig and the keys minikube
#     copies there are readable by the current user only;
#   - KUBECONFIG and MINIKUBE_HOME point into TRIAL_DIR: ~/.kube/config and
#     ~/.minikube are neither read nor written, and minikube only sees its
#     own profile;
#   - images are removed by exact reference only, never with --force: the
#     pinned images of the option before its cold run, and at the end the
#     images this script built or tagged.
# Side effects outside TRIAL_DIR: the Docker image cache (pinned images stay
# cached at the end) and the "kind" Docker network, removed at the end if
# the script created it and nothing uses it. Networks and volumes a tool
# leaves behind under the cluster name are recorded in leftovers.tsv, then
# removed. The functional checks publish ports 16443, 18080, 18081 and 18082
# for a few minutes; 18081 is published without an address on purpose, to
# observe the default (nothing listens behind it). Run it on a trusted
# network: k3d publishes its API and its registry on every interface.
#
# One file above the usual 800-line ceiling, on purpose: the script is run on
# its own, by hand or by a reviewer, and must stay readable and copyable
# without a library next to it.
set -euo pipefail
umask 077

# --- Pinned versions ----------------------------------------------------------

readonly K3D_VERSION="v5.9.0"
readonly KIND_VERSION="v0.33.0"
readonly MINIKUBE_VERSION="v1.39.0"
readonly K8S_VERSION="v1.36.4"
readonly KUBECTL_MINORS="35 36 37"  # client within one minor of the server

# k3d 5.9.0 defaults to k3s v1.36.4-k3s1. k3d reads the k3s version from the
# tag, so the image is passed by tag and its digest checked after the pull.
readonly K3S_IMAGE="rancher/k3s:v1.36.4-k3s1"
readonly K3S_DIGEST="sha256:edad48e12bf81c3a09ac1c05c0c0ffaaa22145980b989d6fae84543a76b83657"
readonly K3D_PROXY_IMAGE="ghcr.io/k3d-io/k3d-proxy:5.9.0"
readonly K3D_TOOLS_IMAGE="ghcr.io/k3d-io/k3d-tools:5.9.0"
# kind v0.33.0 release notes: node images must be used with their digest.
readonly KIND_IMAGE="kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed"
# Default --base-image of minikube v1.39.0, checked at start-up.
readonly KICBASE_IMAGE="gcr.io/k8s-minikube/kicbase:v0.0.51@sha256:4a1c825b61479e6c898851ea66f13c620aaeab6002746e95067fc2c4b38a0b24"
# Base of the local test image (busybox httpd).
readonly BUSYBOX_IMAGE="busybox:1.37.0@sha256:a7dbc319b1438115a207e11930dc4bb3e643dcb3ec0bdd694bb36cd8fad289ec"
readonly GATEWAY_API_VERSION="v1.7.0"
# Immutable release with a release attestation. The file is downloaded with gh
# into TRIAL_DIR and applied only if its SHA-256 matches (1 188 103 bytes,
# read on 2026-11-19).
readonly GATEWAY_API_REPO="kubernetes-sigs/gateway-api"
readonly GATEWAY_API_FILE="standard-install.yaml"
readonly GATEWAY_CRDS_SHA256="4e2602c4cbe1afbc394d86f4ac6522e1a5263b01133bba1e40a6d1a549e753a1"

readonly CLUSTER="celian-bench-003"
readonly HELLO_IMAGE="celian-bench-003-hello:1"
readonly HELLO_MARKER="celian-bench-003 ok"
readonly API_PORT=16443
readonly PORT_LOOPBACK=18080
readonly PORT_DEFAULT=18081
readonly PORT_PROXY=18082  # k3d only: same NodePort through k3d's load balancer
readonly NODEPORT_LOOPBACK=30080
readonly NODEPORT_DEFAULT=30081
readonly SAMPLES=3
readonly SAMPLE_GAP=10
readonly PAUSE_BETWEEN_RUNS=15
readonly READY_TIMEOUT=900
readonly READY_STREAK=3

OPTIONS="${OPTIONS:-k3d kind minikube}"
RUNS="${RUNS:-3}"
COLD="${COLD:-1}"
FUNCTIONAL="${FUNCTIONAL:-1}"
IDLE_WAIT="${IDLE_WAIT:-120}"
readonly OPTIONS RUNS COLD FUNCTIONAL IDLE_WAIT

TRIAL_DIR=""
LOGS=""
KIND_NETWORK_EXISTED=0
GATEWAY_API_LOCAL=""
GATEWAY_API_SKIP=""
CREATED_IMAGES=""

# --- Helpers ------------------------------------------------------------------

log() { printf '[bench-003 %s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die() {
  log "ERROR: $*"
  exit 1
}
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
seconds_between() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", b - a }'; }
utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Append one tab-separated line to a file.
tsv() {
  local file=$1
  shift
  local IFS=$'\t'
  printf '%s\n' "$*" >>"$TRIAL_DIR/$file"
}

# Median and range (max - min) of numbers read on stdin, one per line.
median_range() {
  sort -n | awk '{ v[NR] = $1 } END {
    if (NR == 0) { print "-\t-"; exit }
    m = (NR % 2) ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2
    printf "%.1f\t%.1f\n", m, v[NR] - v[1] }'
}

kube() { kubectl --request-timeout=10s "$@"; }

# --- Cluster identity ---------------------------------------------------------

cluster_filter() {
  case $1 in
    k3d) echo "label=k3d.cluster=$CLUSTER" ;;
    kind) echo "label=io.x-k8s.kind.cluster=$CLUSTER" ;;
    minikube) echo "label=name.minikube.sigs.k8s.io=$CLUSTER" ;;
  esac
}

cluster_containers() {
  docker ps -a --filter "$(cluster_filter "$1")" --format '{{.Names}}' | sort
}

# Running cluster containers only (k3d's tools container is short-lived).
cluster_running() {
  docker ps --filter "$(cluster_filter "$1")" --format '{{.Names}}' | sort
}

pinned_images() {
  case $1 in
    k3d) printf '%s\n' "$K3S_IMAGE" "$K3D_PROXY_IMAGE" "$K3D_TOOLS_IMAGE" ;;
    kind) printf '%s\n' "$KIND_IMAGE" ;;
    minikube) printf '%s\n' "$KICBASE_IMAGE" ;;
  esac
}

# "repo:tag@sha256:x" can be stored as "repo:tag" and as "repo@sha256:x".
image_ref_variants() {
  local ref=$1 repo_tag digest
  case $ref in
    *@sha256:*)
      repo_tag=${ref%@*}
      digest=${ref#*@}
      printf '%s\n' "$repo_tag" "${repo_tag%:*}@$digest"
      ;;
    *) printf '%s\n' "$ref" ;;
  esac
}

image_present() {
  local variant
  for variant in $(image_ref_variants "$1"); do
    if docker image inspect "$variant" >/dev/null 2>&1; then return 0; fi
  done
  return 1
}

# minikube keeps its state in $MINIKUBE_HOME/.minikube; find it either way.
minikube_preloads() {
  find "$MINIKUBE_HOME" -path '*preloaded-tarball/*' -type f -name '*.tar*' 2>/dev/null || true
}

image_remove() {
  local variant
  for variant in $(image_ref_variants "$1"); do
    if docker image inspect "$variant" >/dev/null 2>&1; then
      docker image rm "$variant" >>"$LOGS/images.log" 2>&1 ||
        log "could not remove $variant (in use?), left in place"
    fi
  done
}

# cold: no pinned image present; warm: all present; partial otherwise.
cache_state() {
  local opt=$1 ref present=0 total=0
  for ref in $(pinned_images "$opt"); do
    total=$((total + 1))
    if image_present "$ref"; then present=$((present + 1)); fi
  done
  if [ "$opt" = minikube ]; then
    total=$((total + 1))
    if [ -n "$(minikube_preloads)" ]; then present=$((present + 1)); fi
  fi
  if [ "$present" -eq 0 ]; then
    echo cold
  elif [ "$present" -eq "$total" ]; then
    echo warm
  else
    echo partial
  fi
}

# --- Create, wait, delete -----------------------------------------------------

create_default() {
  case $1 in
    k3d) k3d cluster create "$CLUSTER" --image "$K3S_IMAGE" --timeout 600s ;;
    kind) kind create cluster --name "$CLUSTER" --image "$KIND_IMAGE" --kubeconfig "$KUBECONFIG" ;;
    minikube)
      minikube start -p "$CLUSTER" --driver=docker --interactive=false \
        --kubernetes-version="$K8S_VERSION"
      ;;
  esac
}

delete_cluster() {
  case $1 in
    k3d) k3d cluster delete "$CLUSTER" ;;
    kind) kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" ;;
    minikube) minikube delete -p "$CLUSTER" ;;
  esac
}

wait_gone() {
  local opt=$1 deadline
  deadline=$(($(date +%s) + 180))
  while [ -n "$(cluster_containers "$opt")" ]; do
    [ "$(date +%s)" -lt "$deadline" ] || return 1
    sleep 0.5
  done
}

# Networks and volumes the tools should remove with the cluster, matched by
# exact name. They are recorded, then removed when nothing uses them.
sweep_leftovers() {
  local opt=$1 phase=$2 name
  for name in $(docker network ls --format '{{.Name}}'); do
    case $name in
      "$CLUSTER" | "k3d-$CLUSTER")
        if [ "$(docker network inspect "$name" --format '{{len .Containers}}')" = 0 ] &&
          docker network rm "$name" >>"$LOGS/leftovers.log" 2>&1; then
          tsv leftovers.tsv "$opt" "$phase" network "$name" removed
        else
          tsv leftovers.tsv "$opt" "$phase" network "$name" "left in place"
        fi
        ;;
    esac
  done
  for name in $(docker volume ls -q); do
    case $name in
      "$CLUSTER" | "$CLUSTER"-m0[0-9] | "k3d-$CLUSTER-images")
        if docker volume rm "$name" >>"$LOGS/leftovers.log" 2>&1; then
          tsv leftovers.tsv "$opt" "$phase" volume "$name" removed
        else
          tsv leftovers.tsv "$opt" "$phase" volume "$name" "left in place"
        fi
        ;;
    esac
  done
}

# jq filter: every kube-system workload is done. A failed pod is accepted
# only when its Job eventually succeeded (k3s Helm install jobs can retry).
# shellcheck disable=SC2016 # jq variables, not shell ones
readonly KUBE_SYSTEM_READY='
  [.items[] | select(.kind == "Pod")] as $pods
  | [.items[] | select(.kind == "Job")] as $jobs
  | [$jobs[] | select((.status.succeeded // 0) >= (.spec.completions // 1)) | .metadata.name] as $done
  | ($pods | length) > 0
  and all($pods[];
      .status.phase == "Succeeded"
      or (.status.phase == "Running"
          and any(.status.conditions[]?; .type == "Ready" and .status == "True"))
      or (.status.phase == "Failed"
          and any(.metadata.ownerReferences[]?; .kind == "Job" and (.name as $n | any($done[]; . == $n)))))
  and all(.items[] | select(.kind == "Deployment");
      (.status.availableReplicas // 0) >= .spec.replicas
      and (.status.updatedReplicas // 0) >= .spec.replicas)
  and all(.items[] | select(.kind == "DaemonSet");
      (.status.desiredNumberScheduled // 0) > 0
      and (.status.numberReady // 0) >= .status.desiredNumberScheduled)
  and all($jobs[]; (.status.succeeded // 0) >= (.spec.completions // 1))'

is_ready() {
  local opt=$1 expected_nodes=$2 nodes kube_system charts jobs_done
  nodes=$(kube get nodes -o json 2>/dev/null) || return 1
  printf '%s' "$nodes" | jq -e --argjson n "$expected_nodes" '
    (.items | length) == $n
    and all(.items[]; any(.status.conditions[]?; .type == "Ready" and .status == "True"))' \
    >/dev/null || return 1
  kube_system=$(kube get pods,deployments,daemonsets,jobs -n kube-system -o json 2>/dev/null) || return 1
  printf '%s' "$kube_system" | jq -e "$KUBE_SYSTEM_READY" >/dev/null || return 1
  if [ "$opt" = k3d ]; then
    # k3s installs Traefik through HelmChart objects: each needs its job done.
    charts=$(kube get helmcharts.helm.cattle.io -n kube-system -o name 2>/dev/null | wc -l) || return 1
    jobs_done=$(printf '%s' "$kube_system" | jq '[.items[] | select(.kind == "Job"
      and (.metadata.name | startswith("helm-install-"))
      and (.status.succeeded // 0) >= 1)] | length')
    [ "$charts" -gt 0 ] && [ "$jobs_done" -ge "$charts" ] || return 1
  fi
}

# Prints the time of the first check of READY_STREAK consecutive successes.
wait_ready() {
  local opt=$1 expected_nodes=$2 deadline streak=0 first=""
  deadline=$(($(date +%s) + READY_TIMEOUT))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    local t
    t=$(now)
    if is_ready "$opt" "$expected_nodes"; then
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

# --- Records ------------------------------------------------------------------

# Load average, the cluster's own containers, and only a count of the other
# running containers: their names belong to other projects.
record_load() {
  local opt=$1 phase=$2 loadavg containers total mine
  loadavg=$(uptime | sed -e 's/.*load average[s]*: //' -e 's/,//g')
  containers=$(cluster_running "$opt" | paste -sd, -)
  total=$(docker ps -q | wc -l | tr -d ' ')
  mine=$(cluster_running "$opt" | grep -c . || true)
  tsv load.tsv "$(utc_now)" "$opt" "$phase" "$loadavg" "${containers:--}" "$((total - mine))"
}

# Published ports of every cluster container, and the macOS listener of the
# API server port taken from the kubeconfig.
record_ports() {
  local opt=$1 phase=$2 server port listeners name ports
  docker ps --filter "$(cluster_filter "$opt")" --format '{{.Names}}\t{{.Ports}}' |
    while IFS=$'\t' read -r name ports; do
      tsv ports.tsv "$opt" "$phase" container "$name" "${ports:--}"
    done
  server=$(kube config view --minify -o jsonpath='{.clusters[0].cluster.server}')
  port=${server##*:}
  listeners=$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null |
    awk 'NR > 1 { print $1 "=" $9 }' | sort -u | paste -sd, -)
  tsv ports.tsv "$opt" "$phase" api-server "$server" "-" "${listeners:--}"
}

to_mib_awk='function to_mib(v,  n, u) {
  n = v; sub(/[A-Za-z]+$/, "", n); u = v; sub(/^[0-9.]+/, "", u)
  if (u == "B") return n / 1048576
  if (u == "KiB" || u == "kB") return n / 1024
  if (u == "MiB" || u == "MB") return n
  if (u == "GiB" || u == "GB") return n * 1024
  return -1 }'

# One docker stats sample; prints "cpu_percent<TAB>mem_mib" for the cluster.
idle_sample() {
  local opt=$1 run=$2 sample=$3 names stats
  read -r -a names <<<"$(cluster_running "$opt" | tr '\n' ' ')"
  [ "${#names[@]}" -gt 0 ] || die "$opt: no running cluster container to sample"
  stats=$(docker stats --no-stream --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' "${names[@]}")
  printf '%s\n' "$stats" | awk -F'\t' -v opt="$opt" -v run="$run" -v s="$sample" \
    -v out="$TRIAL_DIR/idle-samples.tsv" "$to_mib_awk"'
    { cpu = $2; sub(/%/, "", cpu); split($3, m, " "); mib = to_mib(m[1])
      printf "%s\t%s\t%s\t%s\t%.2f\t%.1f\n", opt, run, s, $1, cpu, mib >> out
      tc += cpu; tm += mib }
    END { printf "%.2f\t%.1f\n", tc, tm }'
}

# --- One timed run ------------------------------------------------------------

timed_run() {
  local opt=$1 run=$2 cache log_file t0 t1 t_ready t_del0 t_del1 wake started
  local version runtime pods node_mib pulls cpu mem samples="" i sample
  cache=$(cache_state "$opt")
  log_file="$LOGS/$opt-run-$run.log"
  record_load "$opt" "run-$run"
  log "$opt run $run ($cache): create"
  started=$(utc_now)
  t0=$(now)
  create_default "$opt" >"$log_file" 2>&1 || die "$opt create failed, see $log_file"
  t1=$(now)
  t_ready=$(wait_ready "$opt" 1) || die "$opt not ready after ${READY_TIMEOUT}s"
  log "$opt run $run: ready in $(seconds_between "$t0" "$t_ready") s"

  version=$(kube version -o json | jq -r '.serverVersion.gitVersion')
  runtime=$(kube get nodes -o json | jq -r '.items[0].status.nodeInfo.containerRuntimeVersion')
  pods=$(kube get pods -n kube-system --no-headers | wc -l | tr -d ' ')
  record_ports "$opt" "run-$run"

  wake=$(awk -v t="$t_ready" -v w="$IDLE_WAIT" -v n="$(now)" 'BEGIN { d = t + w - n; printf "%.1f", (d > 0 ? d : 0) }')
  sleep "$wake"
  for i in $(seq 1 "$SAMPLES"); do
    sample=$(idle_sample "$opt" "$run" "$i")
    samples="$samples$sample"$'\n'
    if [ "$i" -lt "$SAMPLES" ]; then sleep "$SAMPLE_GAP"; fi
  done
  cpu=$(printf '%s' "$samples" | cut -f1 | grep . | median_range | cut -f1)
  mem=$(printf '%s' "$samples" | cut -f2 | grep . | median_range | cut -f1)

  # Images inside the node(s), and whether the runtime pulled or reused them.
  # Sum of the sizes the kubelet reports for every image on the node, the ones
  # already present included: an upper bound of what was transferred.
  node_mib=$(kube get nodes -o json | jq '[.items[].status.images[]?.sizeBytes] | add // 0 | . / 1048576 | floor')
  pulls=$(kube get events -A -o json | jq -r '[.items[] | select(.reason == "Pulled") | .message] |
    "\(map(select(test("Successfully pulled"))) | length)\t\(map(select(test("already present"))) | length)"')
  record_node_images "$opt" "run-$run"

  log "$opt run $run: delete"
  t_del0=$(now)
  delete_cluster "$opt" >>"$log_file" 2>&1 || die "$opt delete failed, see $log_file"
  wait_gone "$opt" || die "$opt containers still present after delete"
  t_del1=$(now)
  sweep_leftovers "$opt" "run-$run"

  tsv runs.tsv "$opt" "$run" "$cache" "$(seconds_between "$t0" "$t1")" \
    "$(seconds_between "$t0" "$t_ready")" "$(seconds_between "$t_del0" "$t_del1")" \
    "$version" "$runtime" "$pods" "$mem" "$cpu" "$node_mib" "$pulls" "$started"
}

# Images the node runtime pulled from the network, or found already present,
# read from the Pulled events: the references feed the report and R-25.
record_node_images() {
  local opt=$1 phase=$2 status image
  kube get events -A -o json | jq -r '.items[] | select(.reason == "Pulled") | .message' |
    sed -n -e 's/^Successfully pulled image "\([^"]*\)".*/pulled|\1/p' \
      -e 's/^Container image "\([^"]*\)" already present.*/present|\1/p' |
    sort -u | while IFS='|' read -r status image; do
      tsv node-images.tsv "$opt" "$phase" "$status" "$image"
    done
}

# Compressed size per architecture (layers plus config) from the registry
# manifest, read with docker manifest inspect: no pull, no container.
registry_sizes() {
  local query sizes
  query=$(image_ref_variants "$1" | tail -1)
  sizes=$(docker manifest inspect -v "$query" 2>/dev/null | jq -r '
    [if type == "array" then .[] else . end
     | select(.Descriptor.platform.os == "linux")
     | (.SchemaV2Manifest // .OCIManifest) as $m
     | "\(.Descriptor.platform.architecture)=\(([$m.layers[]?.size] | add) + ($m.config.size // 0))"]
    | map(select(startswith("arm64=") or startswith("amd64="))) | join(",")' 2>/dev/null || true)
  echo "${sizes:--}"
}

record_images() {
  local opt=$1 ref variant size digests
  for ref in $(pinned_images "$opt"); do
    size="-"
    digests="-"
    for variant in $(image_ref_variants "$ref"); do
      if docker image inspect "$variant" >/dev/null 2>&1; then
        size=$(docker image inspect --format '{{.Size}}' "$variant")
        digests=$(docker image inspect --format '{{join .RepoDigests ","}}' "$variant")
        break
      fi
    done
    tsv images.tsv "$opt" "$ref" "$size" "$digests" "$(registry_sizes "$ref")"
  done
  if [ "$opt" = minikube ]; then
    for ref in $(minikube_preloads); do
      tsv images.tsv minikube "preload:$(basename "$ref")" "$(wc -c <"$ref" | tr -d ' ')" "-" "-"
    done
  fi
  if [ "$opt" = k3d ] && image_present "$K3S_IMAGE"; then
    case $(docker image inspect --format '{{join .RepoDigests ","}}' "$K3S_IMAGE") in
      *"$K3S_DIGEST"*) log "k3s image digest matches $K3S_DIGEST" ;;
      *) die "k3s image digest differs from $K3S_DIGEST" ;;
    esac
  fi
}

series() {
  local opt=$1 run ref first=1
  record_load "$opt" series-start
  if [ "$COLD" = 1 ]; then
    log "$opt: removing pinned images for the cold run"
    for ref in $(pinned_images "$opt"); do image_remove "$ref"; done
    timed_run "$opt" 0
    record_images "$opt"
    first=0
  fi
  # A counter, not seq: BSD seq counts down when RUNS=0.
  run=1
  while [ "$run" -le "$RUNS" ]; do
    if [ "$first" = 0 ]; then sleep "$PAUSE_BETWEEN_RUNS"; fi
    first=0
    timed_run "$opt" "$run"
    run=$((run + 1))
  done
  if [ "$COLD" != 1 ]; then record_images "$opt"; fi
}

# --- Functional checks --------------------------------------------------------

check() {
  local opt=$1 name=$2 result=$3 detail=$4 command=$5
  log "$opt $name: $result ($detail)"
  tsv functional.tsv "$opt" "$name" "$result" "$detail" "$command"
}

build_hello_image() {
  local dir="$TRIAL_DIR/hello"
  if image_present "$HELLO_IMAGE"; then return 0; fi
  mkdir -p "$dir"
  printf '%s\n' "$HELLO_MARKER" >"$dir/index.html"
  # umask 077 would make it unreadable for httpd, which runs as user 65534.
  chmod 644 "$dir/index.html"
  cat >"$dir/Dockerfile" <<EOF
FROM $BUSYBOX_IMAGE
COPY index.html /www/index.html
USER 65534
EXPOSE 8080
CMD ["httpd", "-f", "-p", "8080", "-h", "/www"]
EOF
  docker build -q -t "$HELLO_IMAGE" "$dir" >>"$LOGS/build.log" 2>&1 || die "image build failed"
  CREATED_IMAGES="$CREATED_IMAGES $HELLO_IMAGE"
}

hello_manifest() {
  local name=$1 image=$2 policy=$3 node_port=$4
  cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $name
spec:
  replicas: 1
  selector:
    matchLabels: {app: $name}
  template:
    metadata:
      labels: {app: $name}
    spec:
      containers:
        - name: hello
          image: $image
          imagePullPolicy: $policy
          ports: [{containerPort: 8080}]
EOF
  if [ -n "$node_port" ]; then
    cat <<EOF
---
apiVersion: v1
kind: Service
metadata:
  name: $name
spec:
  type: NodePort
  selector: {app: $name}
  ports: [{port: 8080, targetPort: 8080, nodePort: $node_port}]
EOF
  fi
}

http_has_marker() {
  local port=$1 deadline
  deadline=$(($(date +%s) + 60))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if printf 'GET / HTTP/1.0\r\nHost: localhost\r\n\r\n' |
      nc -w 5 127.0.0.1 "$port" 2>/dev/null | grep -q "$HELLO_MARKER"; then
      return 0
    fi
    sleep 2
  done
  return 1
}

create_functional() {
  local opt=$1 config="$TRIAL_DIR/kind-functional.yaml"
  case $opt in
    k3d)
      # ":direct" publishes on the node container itself; without a suffix
      # k3d goes through its nginx load balancer ("proxy"), its default.
      k3d cluster create "$CLUSTER" --image "$K3S_IMAGE" --timeout 600s \
        --api-port "127.0.0.1:$API_PORT" \
        -p "127.0.0.1:$PORT_LOOPBACK:$NODEPORT_LOOPBACK@server:0:direct" \
        -p "127.0.0.1:$PORT_PROXY:$NODEPORT_LOOPBACK@server:0" \
        -p "$PORT_DEFAULT:$NODEPORT_DEFAULT@server:0" \
        --registry-create "$CLUSTER-registry"
      ;;
    kind)
      cat >"$config" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: $NODEPORT_LOOPBACK
        hostPort: $PORT_LOOPBACK
        listenAddress: "127.0.0.1"
      - containerPort: $NODEPORT_DEFAULT
        hostPort: $PORT_DEFAULT
EOF
      kind create cluster --name "$CLUSTER" --image "$KIND_IMAGE" \
        --kubeconfig "$KUBECONFIG" --config "$config"
      ;;
    minikube)
      minikube start -p "$CLUSTER" --driver=docker --interactive=false \
        --kubernetes-version="$K8S_VERSION" \
        --ports="127.0.0.1:$PORT_LOOPBACK:$NODEPORT_LOOPBACK" \
        --ports="$PORT_DEFAULT:$NODEPORT_DEFAULT"
      ;;
  esac
}

load_hello() {
  case $1 in
    k3d) k3d image import "$HELLO_IMAGE" -c "$CLUSTER" ;;
    kind) kind load docker-image "$HELLO_IMAGE" --name "$CLUSTER" ;;
    minikube) minikube -p "$CLUSTER" image load "$HELLO_IMAGE" ;;
  esac
}

load_hello_command() {
  case $1 in
    k3d) echo "k3d image import $HELLO_IMAGE -c $CLUSTER" ;;
    kind) echo "kind load docker-image $HELLO_IMAGE --name $CLUSTER" ;;
    minikube) echo "minikube -p $CLUSTER image load $HELLO_IMAGE" ;;
  esac
}

# Push the local image to the option's registry, then run it from there.
check_registry() {
  local opt=$1 log_file=$2 name host_ports host_port pushed pull_ref t0
  case $opt in
    kind)
      check kind registry no "not built in; the documented script starts registry:3 with docker run, not run here" \
        "https://kind.sigs.k8s.io/docs/user/local-registry/"
      return 0
      ;;
    k3d)
      name=$(k3d registry list -o json | jq -r --arg n "$CLUSTER-registry" '.[] | select(.name == $n) | .name')
      if [ -z "$name" ]; then
        check k3d registry no "registry $CLUSTER-registry not found" "k3d registry list"
        return 0
      fi
      pull_ref="$name:5000/celian-bench-003-hello:1"
      ;;
    minikube)
      t0=$(now)
      if ! minikube -p "$CLUSTER" addons enable registry >>"$log_file" 2>&1; then
        check minikube registry no "addon enable failed" "minikube -p $CLUSTER addons enable registry"
        return 0
      fi
      # The addon's pods appear a moment after the command returns.
      sleep 5
      if ! wait_ready minikube 1 >/dev/null; then
        check minikube registry no "kube-system not ready after the addon" "minikube -p $CLUSTER addons enable registry"
        return 0
      fi
      log "minikube registry addon ready in $(seconds_between "$t0" "$(now)") s"
      name=$CLUSTER
      pull_ref="localhost:5000/celian-bench-003-hello:1"
      ;;
  esac
  host_ports=$(docker port "$name" 5000/tcp | paste -sd, -)
  tsv ports.tsv "$opt" functional registry "$name" "5000/tcp -> $host_ports" "-"
  host_port=$(docker port "$name" 5000/tcp | head -1)
  record_listeners "$opt" functional "${host_port##*:}"
  pushed="127.0.0.1:${host_port##*:}/celian-bench-003-hello:1"
  docker tag "$HELLO_IMAGE" "$pushed"
  CREATED_IMAGES="$CREATED_IMAGES $pushed"
  if ! docker push "$pushed" >>"$log_file" 2>&1; then
    check "$opt" registry no "docker push $pushed failed" "docker push $pushed"
    return 0
  fi
  hello_manifest hello-registry "$pull_ref" Always "" | kube apply -f - >>"$log_file" 2>&1
  if kube rollout status deployment/hello-registry --timeout=120s >>"$log_file" 2>&1; then
    check "$opt" registry yes "pushed to $pushed, pod pulled $pull_ref" "docker push $pushed"
  else
    check "$opt" registry no "pod could not pull $pull_ref" "docker push $pushed"
  fi
}

gateway_bundle_version() {
  kube get crd gateways.gateway.networking.k8s.io \
    -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}' 2>/dev/null || true
}

gateway_established() {
  kube wait --for=condition=Established --timeout=60s \
    crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io \
    crd/httproutes.gateway.networking.k8s.io
}

# Download the CRD bundle once with gh, then check its SHA-256 before any use.
# Sets GATEWAY_API_LOCAL on success, GATEWAY_API_SKIP with the reason otherwise.
fetch_gateway_api() {
  local dir="$TRIAL_DIR/gateway-api" sum
  if [ -n "$GATEWAY_API_LOCAL" ] || [ -n "$GATEWAY_API_SKIP" ]; then return 0; fi
  if ! command -v gh >/dev/null || ! command -v shasum >/dev/null; then
    GATEWAY_API_SKIP="gh or shasum not found"
    return 0
  fi
  mkdir -p "$dir"
  if ! gh release download "$GATEWAY_API_VERSION" -R "$GATEWAY_API_REPO" \
    -p "$GATEWAY_API_FILE" -D "$dir" >>"$LOGS/gateway-api.log" 2>&1; then
    GATEWAY_API_SKIP="gh release download failed, see logs/gateway-api.log"
    return 0
  fi
  sum=$(shasum -a 256 "$dir/$GATEWAY_API_FILE" | awk '{ print $1 }')
  if [ "$sum" != "$GATEWAY_CRDS_SHA256" ]; then
    GATEWAY_API_SKIP="SHA-256 $sum differs from the pinned $GATEWAY_CRDS_SHA256"
    return 0
  fi
  GATEWAY_API_LOCAL="$dir/$GATEWAY_API_FILE"
}

check_gateway_api() {
  local opt=$1 log_file=$2 before before_version owner rc=0 apply
  before=$(kube get crd -o name | grep -c 'gateway.networking.k8s.io' || true)
  before_version=$(gateway_bundle_version)
  if [ "$before" -gt 0 ]; then
    check "$opt" gateway-api-preinstalled yes "$before CRDs before install, bundle-version ${before_version:-none}" "kubectl get crd"
  else
    check "$opt" gateway-api-preinstalled no "no Gateway API CRD before install" "kubectl get crd"
  fi
  apply="gh release download $GATEWAY_API_VERSION -R $GATEWAY_API_REPO -p $GATEWAY_API_FILE, SHA-256 checked, kubectl apply --server-side -f <trial>/gateway-api/$GATEWAY_API_FILE"
  fetch_gateway_api
  if [ -z "$GATEWAY_API_LOCAL" ]; then
    check "$opt" gateway-api-crds skipped "$GATEWAY_API_SKIP" "$apply"
    return 0
  fi
  kube apply --server-side -f "$GATEWAY_API_LOCAL" >>"$log_file" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ] && gateway_established >>"$log_file" 2>&1; then
    check "$opt" gateway-api-crds yes "standard channel, bundle-version $(gateway_bundle_version), Established" "$apply"
    return 0
  fi
  owner=$(grep -o 'conflicts with "[^"]*"' "$log_file" | sed 's/conflicts with //' | sort -u | paste -sd, - || true)
  if [ -n "$owner" ]; then
    check "$opt" gateway-api-crds no "exit code $rc, conflicts with field manager $owner" "$apply"
  else
    check "$opt" gateway-api-crds no "exit code $rc, no conflict reported" "$apply"
  fi
  [ -n "$owner" ] || return 0
  rc=0
  kube apply --server-side --force-conflicts -f "$GATEWAY_API_LOCAL" >>"$log_file" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ] && gateway_established >>"$log_file" 2>&1; then
    check "$opt" gateway-api-crds-forced yes "bundle-version $(gateway_bundle_version) after taking the fields of field manager $owner" \
      "same file, kubectl apply --server-side --force-conflicts"
  else
    check "$opt" gateway-api-crds-forced no "exit code $rc" "same file, kubectl apply --server-side --force-conflicts"
  fi
}

# macOS (or Linux) listeners of host ports, to see what the engine exposes.
record_listeners() {
  local opt=$1 phase=$2 port listeners
  shift 2
  for port in "$@"; do
    listeners=$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null |
      awk 'NR > 1 { print $1 "=" $9 }' | sort -u | paste -sd, -)
    tsv ports.tsv "$opt" "$phase" host-port "$port" "-" "${listeners:--}"
  done
}

create_multinode() {
  local opt=$1 config="$TRIAL_DIR/kind-multinode.yaml"
  case $opt in
    k3d) k3d cluster create "$CLUSTER" --image "$K3S_IMAGE" --timeout 600s --agents 1 ;;
    kind)
      printf '%s\n' "kind: Cluster" "apiVersion: kind.x-k8s.io/v1alpha4" "nodes:" \
        "  - role: control-plane" "  - role: worker" >"$config"
      kind create cluster --name "$CLUSTER" --image "$KIND_IMAGE" \
        --kubeconfig "$KUBECONFIG" --config "$config"
      ;;
    minikube)
      minikube start -p "$CLUSTER" --driver=docker --interactive=false \
        --kubernetes-version="$K8S_VERSION" --nodes=2
      ;;
  esac
}

multinode_command() {
  case $1 in
    k3d) echo "k3d cluster create $CLUSTER --agents 1" ;;
    kind) echo "kind create cluster --config (control-plane + worker)" ;;
    minikube) echo "minikube start -p $CLUSTER --nodes=2" ;;
  esac
}

check_port() {
  local opt=$1 name=$2 port=$3 how=$4
  if http_has_marker "$port"; then
    check "$opt" "$name" yes "HTTP 127.0.0.1:$port reaches NodePort $NODEPORT_LOOPBACK ($how)" \
      "host port $port -> NodePort $NODEPORT_LOOPBACK"
  else
    check "$opt" "$name" no "TCP accepted or refused, no HTTP answer on 127.0.0.1:$port within 60 s ($how)" \
      "host port $port -> NodePort $NODEPORT_LOOPBACK"
  fi
}

functional() {
  local opt=$1 log_file t0 t_ready
  log_file="$LOGS/$opt-functional.log"
  record_load "$opt" functional
  log "$opt functional: create with published ports"
  if ! create_functional "$opt" >"$log_file" 2>&1; then
    check "$opt" create-functional no "creation failed, see $log_file" "create with ports"
    delete_cluster "$opt" >>"$log_file" 2>&1 || true
    return 0
  fi
  wait_ready "$opt" 1 >/dev/null || die "$opt functional cluster not ready"
  record_ports "$opt" functional
  record_listeners "$opt" functional "$PORT_LOOPBACK" "$PORT_DEFAULT"

  build_hello_image
  t0=$(now)
  if load_hello "$opt" >>"$log_file" 2>&1; then
    check "$opt" image-load yes "loaded in $(seconds_between "$t0" "$(now)") s, run with imagePullPolicy Never" \
      "$(load_hello_command "$opt")"
  else
    check "$opt" image-load no "see $log_file" "$(load_hello_command "$opt")"
  fi
  hello_manifest hello "$HELLO_IMAGE" Never "$NODEPORT_LOOPBACK" | kube apply -f - >>"$log_file" 2>&1
  if kube rollout status deployment/hello --timeout=120s >>"$log_file" 2>&1; then
    if [ "$opt" = k3d ]; then
      check_port k3d port-publish "$PORT_LOOPBACK" "-p @server:0:direct"
      check_port k3d port-publish-proxy "$PORT_PROXY" "-p @server:0, through the k3d load balancer"
      record_listeners k3d functional "$PORT_PROXY"
    else
      check_port "$opt" port-publish "$PORT_LOOPBACK" "published on the node container"
    fi
  else
    check "$opt" port-publish no "deployment hello not ready" "kubectl rollout status deployment/hello"
  fi
  check_registry "$opt" "$log_file"
  check_gateway_api "$opt" "$log_file"
  delete_cluster "$opt" >>"$log_file" 2>&1 || die "$opt functional delete failed"
  wait_gone "$opt" || die "$opt functional containers still present"
  sweep_leftovers "$opt" functional

  sleep "$PAUSE_BETWEEN_RUNS"
  log "$opt functional: two nodes"
  t0=$(now)
  if create_multinode "$opt" >>"$log_file" 2>&1 && t_ready=$(wait_ready "$opt" 2); then
    check "$opt" multi-node yes "2 nodes Ready in $(seconds_between "$t0" "$t_ready") s" "$(multinode_command "$opt")"
    record_ports "$opt" multi-node
  else
    check "$opt" multi-node no "see $log_file" "$(multinode_command "$opt")"
  fi
  delete_cluster "$opt" >>"$log_file" 2>&1 || die "$opt multi-node delete failed"
  wait_gone "$opt" || die "$opt multi-node containers still present"
  sweep_leftovers "$opt" multi-node
}

# --- Start-up checks ----------------------------------------------------------

check_versions() {
  local opt v
  for v in docker kubectl jq perl nc lsof; do
    command -v "$v" >/dev/null || die "$v not found"
  done
  v=$(kubectl version --client -o json | jq -r '.clientVersion.minor' | tr -dc '0-9')
  case " $KUBECTL_MINORS " in
    *" $v "*) ;;
    *) die "kubectl 1.$v is more than one minor away from $K8S_VERSION" ;;
  esac
  tsv versions.tsv kubectl "$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion')"
  for opt in $OPTIONS; do
    case $opt in
      k3d)
        v=$(k3d version | awk 'NR == 1 { print $3 }')
        [ "$v" = "$K3D_VERSION" ] || die "k3d $v found, $K3D_VERSION expected"
        ;;
      kind)
        v=$(kind version | awk '{ print $2 }')
        [ "$v" = "$KIND_VERSION" ] || die "kind $v found, $KIND_VERSION expected"
        ;;
      minikube)
        v=$(minikube version --short)
        [ "$v" = "$MINIKUBE_VERSION" ] || die "minikube $v found, $MINIKUBE_VERSION expected"
        minikube start --help 2>/dev/null | grep -qF "$KICBASE_IMAGE" ||
          die "minikube default base image differs from $KICBASE_IMAGE"
        ;;
      *) die "unknown option: $opt" ;;
    esac
    tsv versions.tsv "$opt" "$v"
  done
  tsv versions.tsv docker "$(docker version --format '{{.Server.Version}}')"
  tsv versions.tsv engine "$(docker info --format '{{.OperatingSystem}} {{.NCPU}} CPU {{.MemTotal}} B cgroup v{{.CgroupVersion}}')"
  tsv versions.tsv host "$(sysctl -n hw.model 2>/dev/null || uname -m) $(sw_vers -productVersion 2>/dev/null || uname -r)"
}

check_no_cluster() {
  local opt
  for opt in k3d kind minikube; do
    [ -z "$(cluster_containers "$opt")" ] || die "a $opt cluster named $CLUSTER already exists"
  done
  [ -z "$(docker ps -aq --filter "name=^/?$CLUSTER")" ] || die "a container named $CLUSTER* already exists"
}

check_ports_free() {
  local port
  for port in $API_PORT $PORT_LOOPBACK $PORT_DEFAULT $PORT_PROXY; do
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      die "port $port is already in use"
    fi
  done
}

# --- Cleanup --------------------------------------------------------------------

cleanup() {
  local rc=$? opt ref name
  trap - EXIT INT TERM
  set +e
  if [ -n "$TRIAL_DIR" ]; then
    for opt in k3d kind minikube; do
      if command -v "$opt" >/dev/null && [ -n "$(cluster_containers "$opt")" ]; then
        log "cleanup: deleting the $opt cluster $CLUSTER"
        delete_cluster "$opt" >>"$LOGS/cleanup.log" 2>&1
      fi
      if command -v "$opt" >/dev/null; then sweep_leftovers "$opt" cleanup; fi
    done
    if command -v k3d >/dev/null; then
      for name in $(k3d registry list -o json 2>/dev/null |
        jq -r --arg n "$CLUSTER-registry" '.[] | select(.name == $n) | .name'); do
        log "cleanup: deleting the k3d registry $name"
        k3d registry delete "$name" >>"$LOGS/cleanup.log" 2>&1
      done
    fi
    for ref in $CREATED_IMAGES; do image_remove "$ref"; done
    if [ "$KIND_NETWORK_EXISTED" = 0 ] && docker network inspect kind >/dev/null 2>&1 &&
      [ "$(docker network inspect kind --format '{{len .Containers}}')" = 0 ]; then
      log "cleanup: removing the kind network created by this run"
      docker network rm kind >>"$LOGS/cleanup.log" 2>&1
    fi
    docker volume ls -q | sort >"$TRIAL_DIR/volumes-after.txt"
    log "results in $TRIAL_DIR"
  fi
  exit "$rc"
}

# --- Summary --------------------------------------------------------------------

summarize() {
  local opt column name values
  tsv summary.tsv option metric runs values median range
  for opt in $OPTIONS; do
    for column in 5:ready_s 10:mem_mib 11:cpu_pct 6:delete_s 4:create_cmd_s; do
      name=${column#*:}
      values=$(awk -F'\t' -v o="$opt" -v c="${column%%:*}" \
        '$1 == o && $2 != "run" && $2 != "0" { print $c }' "$TRIAL_DIR/runs.tsv")
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
  mkdir -p "$LOGS"

  # One kubeconfig file, created empty so that every tool writes into it.
  export KUBECONFIG="$TRIAL_DIR/kubeconfig"
  export MINIKUBE_HOME="$TRIAL_DIR/minikube-home"
  export MINIKUBE_IN_STYLE=false
  : >"$KUBECONFIG"
  chmod 600 "$KUBECONFIG"
  mkdir -p "$MINIKUBE_HOME"

  tsv runs.tsv option run cache create_cmd_s ready_s delete_s k8s_version runtime \
    kube_system_pods mem_mib cpu_pct node_images_mib pulled_downloaded pulled_present started_utc
  tsv idle-samples.tsv option run sample container cpu_pct mem_mib
  tsv ports.tsv option phase kind name ports_or_url macos_listeners
  tsv images.tsv option image size_bytes repo_digests compressed_bytes
  tsv node-images.tsv option phase status image
  tsv functional.tsv option check result detail command
  tsv load.tsv utc option phase loadavg_1_5_15 cluster_containers other_containers
  tsv leftovers.tsv option phase type name action
  tsv versions.tsv item version

  # Start-up checks first, without any trap: a refusal to start must not
  # delete anything, neither a cluster of that name nor the "kind" network.
  check_versions
  check_no_cluster
  if docker network inspect kind >/dev/null 2>&1; then KIND_NETWORK_EXISTED=1; fi
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  docker volume ls -q | sort >"$TRIAL_DIR/volumes-before.txt"
  case " $OPTIONS " in
    *" minikube "*) minikube config set WantUpdateNotification false >/dev/null ;;
  esac
  log "trial directory: $TRIAL_DIR"

  for opt in $OPTIONS; do
    series "$opt"
    sleep "$PAUSE_BETWEEN_RUNS"
  done
  if [ "$FUNCTIONAL" = 1 ]; then
    check_ports_free
    for opt in $OPTIONS; do
      functional "$opt"
      sleep "$PAUSE_BETWEEN_RUNS"
    done
  fi
  summarize
  column -t -s "$(printf '\t')" "$TRIAL_DIR/summary.tsv" >&2 || true
}

main "$@"
