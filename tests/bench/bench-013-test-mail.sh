#!/usr/bin/env bash
# BENCH-013: test mail server of the standard profile, measured on kind.
# Options: Mailpit v1.34.0, maildev 3.0.0, smtp4dev 3.16.1, each deployed from
# the manifests of tests/bench/bench-013/ (checked against pinned SHA-256
# sums, images pinned by index digest), under the Restricted Pod Security
# Standard, with web and API credentials read from a Secret that the script
# creates through a pipe (ADR-007).
#
# Commands that create, modify or delete a container or a network ([SECU]
# rule of 2026-11-20). They are all listed here; the script runs no other:
#   - kind create cluster --name celian-bench-013: creates the node container
#     celian-bench-013-control-plane, which kind starts with "docker run
#     --privileged", and the Docker network "kind" if it does not exist yet;
#     pulls the node image if it is missing from the cache;
#   - kind delete cluster --name celian-bench-013: deletes that container. The
#     "kind" network is left in place;
#   - kubectl apply, create and delete, against that cluster only: pods run
#     in the containerd of the node, never as containers of the host engine.
# Read-only Docker commands: docker version, docker info, docker ps -q,
# docker network inspect, docker manifest inspect (registry metadata, no layer
# download), docker stats.
# Outbound reads: docker manifest inspect and node image pulls (Docker Hub).
# Never used: docker run, start, restart, exec, cp, build, pull, rm and
# network rm; kind load; kubectl exec, cp, debug and port-forward; curl, wget,
# python, node, perl.
#
# Each run creates a fresh kind cluster (kind 0.33.0, node image pinned by
# digest, ADR-004) and measures, for one option:
#   M1  installation until "ready": Deployment ready, pod Running and Ready,
#       image pulled by the node;
#   M2  memory at rest: the node container (docker stats) and the option's
#       pod (kubelet Summary API), IDLE_WAIT s after the probe, 3 samples 10 s
#       apart; the layer is node minus the base node (option "none", M7);
#   M3  CPU of the pod at the same moments;
#   M4  compressed size per architecture, read from the platform manifests
#       in the registry (no layer download), and the images the node pulled
#       (Pulled events);
#   M5  one mail sent over SMTP from a probe pod and read back through the
#       HTTP API, timed inside the pod from /proc/uptime;
#   M6  node architecture and platform entries of the image index;
#   M8  API refused without credentials and accepted with them (probe pod);
#       no command or args in the live pod spec, so no secret in argv; the
#       Secret carries no last-applied-configuration annotation.
# Runs are interleaved (option A, option B, ...). An option that does not
# become ready is recorded once, with the reason, and its remaining runs are
# skipped.
#
# Usage: tests/bench/bench-013-test-mail.sh [TRIAL_DIR]
#   TRIAL_DIR, if given, must be missing or empty (default: a new mktemp -d).
#   Environment:
#     OPTIONS="mailpit maildev smtp4dev"  options, interleaved in this order;
#                     "none" is the base node: same cluster, namespace, Secret
#                     and probe Job, no mail server
#     RUNS=3          runs per option
#     IDLE_WAIT=120   seconds between the end of the probe and the 1st sample
#     BENCH_LOCK=DIR  lock directory shared with other benchmarks: created with
#                     mkdir after the start-up checks (exit code 75 if it
#                     exists), holds an "owner" file, removed by the EXIT trap
#     SIZES=1         record the compressed sizes (two manifest requests per
#                     option); 0 skips them, to spare the registry's pull quota
#   Results (TSV) in TRIAL_DIR: versions.tsv, manifests.tsv, images.tsv,
#   runs.tsv, functional.tsv, idle.tsv, node-images.tsv, load.tsv,
#   summary.tsv; command output in TRIAL_DIR/logs/. No credential is ever
#   written there: the Secret is generated in a pipe straight into kubectl.
# Needs: bash >= 3.2, zsh (sub-second clock), docker, kind v0.33.0, kubectl
#   (1.35 to 1.37), jq, shasum, awk.
#
# Safety:
#   - no docker, kind or kubectl command runs before the lock is taken, when
#     BENCH_LOCK is set; only the manifest check comes first;
#   - the cluster is named celian-bench-013. The script refuses to start if it
#     already exists. Until that check passes, the EXIT trap only releases the
#     lock, so a refusal deletes nothing; afterwards it deletes only that
#     cluster;
#   - umask 077; KUBECONFIG points into TRIAL_DIR: ~/.kube is neither read nor
#     written;
#   - no port is published to the host: kind keeps its API on 127.0.0.1 and
#     every test runs from a pod inside the cluster.
set -euo pipefail
umask 077

# --- Pinned versions ----------------------------------------------------------

readonly KIND_VERSION="v0.33.0"
readonly KIND_IMAGE="kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed"
readonly KUBECTL_MINORS="35 36 37"

# Option images: "option reference amd64-manifest arm64-manifest". Index
# digests and per-platform manifest digests read on 2026-11-20 from the
# Docker Hub API (tag endpoints). The script checks, before any run, that the
# pinned index and the tag resolve to these platform manifests.
readonly OPTION_IMAGES="
mailpit axllent/mailpit:v1.34.0@sha256:23a2ef85bc50853ab3093645d1d64679afd8887e89da5e48a88940c172591a4e sha256:5040a9c533087d25dcb8f2ac748f45c9be5f7bc1d9fe5b860afb9597a2471d57 sha256:fbcdc3ae58bf9b84fab363f53cdccb40698cd88e185e910335e812045e78b54b
maildev maildev/maildev:3.0.0@sha256:6e09695961f4aef9016a390ad391314a078220216601b15a35d389a7df2a3855 sha256:14fc33af1b62e1ff35cc2494cad6756c81666499907d6acd9e11b03dbbc115cb sha256:b98b313db6a65562bcc4c6bf5f0d6269d2263ad005e510cf41f6e09b081d2990
smtp4dev rnwood/smtp4dev:3.16.1@sha256:211a60c1a4f51ff7ace4a35de055797348994b0e84ab36734991235f90f9ac75 sha256:3ae6354b60ba93c8cce4f97d202740d7ceb255e35ce80a3fae770289f6160e25 sha256:a6b0eb3dd3122598dfc7d0d46b6172f22543c835956f14bb5edbcd7e28d8c80e
"
readonly PROBE_IMAGE="busybox:1.37.0@sha256:a7dbc319b1438115a207e11930dc4bb3e643dcb3ec0bdd694bb36cd8fad289ec"

# SHA-256 of every manifest file, relative to tests/bench/bench-013/.
readonly MANIFEST_SUMS="
namespace.yaml 85d2cc1e207d3bdea518ffcf9970dcfcac7c69b3d75444ea6ac93a0bd83d213c
mailpit/deployment.yaml 5acbcb25d50ba25cfc5d8ce570b99519f22fff357c0c01db36830405c8fb99f3
mailpit/kustomization.yaml a7df67acd49847a836a019171ab05077ce965e5c73d02f5207c0e4d28a2463a9
mailpit/service.yaml 962df83006ec6d8a5787c7f992d538e660b8886d5bd25daca84f5eae53e9b4ca
maildev/deployment.yaml cc1bc08934544059b1a1805161db3474f0bfe7ee6948048415a22d69e8eb3f7e
maildev/kustomization.yaml f22e12ddb0b475c6d4239aeb43753d5a9ee239f98d5234247683f2a753ea92e5
maildev/service.yaml 1558259740d19cce9d39e746ea8dbde875ccfde8eba744bd35a524b90dba154a
smtp4dev/deployment.yaml b6e97065f27169c3d0440abdef51cbfe5b805d149faedb9c7107832ad71cb811
smtp4dev/kustomization.yaml c904044d52b4a70273af4958522f284eabc7797850bfe992188060f10d534606
smtp4dev/service.yaml 65e4c44f3b4cb28e440e4b44cf27bd431a6fe6cfc698fcc8ebd33ced679e5c31
none/kustomization.yaml 0d9bc050f58dd213fb8187eebe00e420462cb6caa3c83292573cc8cc70b2ab01
probe/job.yaml ded0104547aed454f9bf8fd829d445a475c344822e0c7a3730cce1733ad2d720
probe/kustomization.yaml 5a812bf55c4ccb1993e614ea08b0653a7e727f3083345c793294a566a547daa6
probe/probe.sh 4f091f189ee17079ae67d2124f3cd6fa9b1ff4479fc6ca95c9a62716bbf0c27d
"

readonly CLUSTER="celian-bench-013"
readonly NODE="$CLUSTER-control-plane"
readonly NAMESPACE="mail-test"
readonly UI_USER="celian-bench"
readonly SECRET_LENGTH=32
readonly SAMPLES=3
readonly SAMPLE_GAP=10
readonly PAUSE_BETWEEN_RUNS=15
readonly READY_STREAK=3
readonly CLUSTER_TIMEOUT=300
readonly INSTALL_TIMEOUT=300
readonly PROBE_TIMEOUT=200

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
readonly MANIFESTS="$SCRIPT_DIR/bench-013"

OPTIONS="${OPTIONS:-mailpit maildev smtp4dev}"
RUNS="${RUNS:-3}"
IDLE_WAIT="${IDLE_WAIT:-120}"
BENCH_LOCK="${BENCH_LOCK:-}"
SIZES="${SIZES:-1}"
readonly OPTIONS RUNS IDLE_WAIT BENCH_LOCK SIZES

TRIAL_DIR=""
LOGS=""
LOCK_HELD=0
SKIPPED=""
RUN_OK=1

# --- Helpers ------------------------------------------------------------------

log() { printf '[bench-013 %s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die() {
  log "ERROR: $*"
  exit 1
}
# Sub-second wall clock without perl or python: zsh's EPOCHREALTIME.
now() { zsh -fc 'zmodload zsh/datetime; printf "%.3f\n" $EPOCHREALTIME'; }
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
    printf "%.2f\t%.2f\n", m, v[NR] - v[1] }'
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

is_skipped() { case " $SKIPPED " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

option_field() {
  # $1: option, $2: field number of OPTION_IMAGES (2 image, 3 amd64, 4 arm64)
  printf '%s\n' "$OPTION_IMAGES" | awk -v o="$1" -v f="$2" '$1 == o { print $f }'
}

option_version() {
  case $1 in
    none) echo "-" ;;
    *) option_field "$1" 2 | sed -E 's/^[^:]+:([^@]+)@.*/\1/' ;;
  esac
}

# --- Manifests and images -------------------------------------------------------

verify_manifests() {
  local file expected sum count=0
  while read -r file expected; do
    [ -n "$file" ] || continue
    [ -f "$MANIFESTS/$file" ] || die "missing manifest $file"
    sum=$(shasum -a 256 "$MANIFESTS/$file" | awk '{ print $1 }')
    [ "$sum" = "$expected" ] || die "manifest $file: SHA-256 $sum differs from $expected"
    tsv manifests.tsv "$file" "$sum"
    count=$((count + 1))
  done <<EOF
$MANIFEST_SUMS
EOF
  # Every file of the directory must be pinned, and every image by digest.
  [ "$count" -eq "$(find "$MANIFESTS" -type f | wc -l | tr -d ' ')" ] ||
    die "some files of $MANIFESTS have no pinned SHA-256"
  if grep -rhE '^[[:space:]]*image:' "$MANIFESTS" | grep -v '@sha256:' >/dev/null; then
    die "an image of $MANIFESTS has no digest"
  fi
}

# Registry metadata, with as few manifest requests as possible: Docker Hub
# counts each platform manifest fetched as one pull (100 per 6 hours for an
# anonymous address), and the -v form fetches every platform of an index.
# One retry after 10 s; errors go to logs/registry.log.
registry_get() {
  local try out
  for try in 1 2; do
    if out=$(docker manifest inspect "$1" 2>>"$LOGS/registry.log"); then
      printf '%s\n' "$out"
      return 0
    fi
    log "registry: no answer for $1 (try $try)"
    sleep 10
  done
  return 1
}

# "arch[/variant]=digest" of each linux entry of an index, sorted: one request.
registry_platforms() {
  registry_get "$1" | jq -r '
    [.manifests[]? | select(.platform.os == "linux")
     | "\(.platform.architecture)\(if .platform.variant then "/" + .platform.variant else "" end)=\(.digest)"]
    | sort | join(",")' 2>>"$LOGS/registry.log" || true
}

# Compressed size of one platform manifest: layers plus config.
registry_size() {
  registry_get "$1" | jq -r '([.layers[]?.size] | add) + (.config.size // 0)' 2>>"$LOGS/registry.log" || true
}

# The pinned index and the tag must both list the pinned amd64 and arm64
# manifests; then, if SIZES=1, record their compressed sizes (M4). For the
# probe image, the pinned index only has to resolve.
verify_image() {
  local opt=$1 ref=$2 amd=$3 arm=$4 tag repo pinned by_tag=- sizes=- entries
  tag=${ref%@*}
  repo=${tag%:*}
  pinned="$repo@${ref#*@}"
  entries=$(registry_platforms "$pinned")
  [ -n "$entries" ] || die "$opt: registry did not answer for $pinned, see $LOGS/registry.log"
  if [ -n "$amd" ]; then
    by_tag=$(registry_platforms "$tag")
    [ -n "$by_tag" ] || die "$opt: registry did not answer for $tag, see $LOGS/registry.log"
    for entries in "$entries" "$by_tag"; do
      case ",$entries," in
        *",amd64=$amd,"*) ;;
        *) die "$opt: amd64 manifest of $ref is not $amd ($entries)" ;;
      esac
      case ",$entries," in
        *",arm64=$arm,"*) ;;
        *) die "$opt: arm64 manifest of $ref is not $arm ($entries)" ;;
      esac
    done
    if [ "$SIZES" = 1 ]; then
      sizes="amd64=$(registry_size "$repo@$amd"),arm64=$(registry_size "$repo@$arm")"
    fi
  fi
  tsv images.tsv "$opt" "$ref" "$sizes" "$by_tag"
}

verify_images() {
  local opt
  for opt in $OPTIONS; do
    [ "$opt" != none ] || continue
    verify_image "$opt" "$(option_field "$opt" 2)" "$(option_field "$opt" 3)" "$(option_field "$opt" 4)"
  done
  verify_image probe "$PROBE_IMAGE" "" ""
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
  printf '%s' "$json" | jq -e "$KUBE_SYSTEM_READY" >/dev/null
}

cluster_exists() { kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; }

create_cluster() {
  kind create cluster --name "$CLUSTER" --image "$KIND_IMAGE" --kubeconfig "$KUBECONFIG"
}

delete_cluster() { kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG"; }

# --- Steps of a run ------------------------------------------------------------------

# The Secret is generated in a pipe and handed to kubectl create: the value
# never lands in a file, a variable, an argument or the trial directory. The
# brace group stops pipefail from failing on the SIGPIPE that head sends tr.
create_secret() {
  { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom || true; } | head -c "$SECRET_LENGTH" |
    awk -v ns="$NAMESPACE" -v user="$UI_USER" '{
      printf "apiVersion: v1\nkind: Secret\nmetadata:\n  name: mail-ui-auth\n  namespace: %s\n", ns
      printf "type: Opaque\nstringData:\n  username: \"%s\"\n  password: \"%s\"\n", user, $0
      printf "  mp-ui-auth: \"%s:%s\"\n", user, $0 }' |
    kube create -f -
}

# Length of the password and presence of the last-applied annotation, without
# printing the value.
secret_check() {
  kube get secret mail-ui-auth -n "$NAMESPACE" -o json | jq -r '
    "password_length=\(.data.password | @base64d | length) last_applied=\(.metadata.annotations // {} | has("kubectl.kubernetes.io/last-applied-configuration"))"'
}

# shellcheck disable=SC2016 # jq variables, not shell ones
readonly MAIL_READY='
  [.items[] | select(.kind == "Deployment")] as $d
  | [.items[] | select(.kind == "Pod")] as $p
  | ($d | length) == 1 and ($d[0].status.readyReplicas // 0) >= 1
  and ($p | length) >= 1
  and all($p[]; .status.phase == "Running"
      and any(.status.conditions[]?; .type == "Ready" and .status == "True"))'

mail_ready() {
  local json
  json=$(kube get deployments,pods -n "$NAMESPACE" -l app=mail -o json 2>/dev/null) || return 1
  printf '%s' "$json" | jq -e "$MAIL_READY" >/dev/null
}

# M8, static part on the live pod: no command, no args, credentials only
# through secretKeyRef environment variables.
# shellcheck disable=SC2016 # jq variables, not shell ones
readonly SPEC_CHECK='
  .items[0].spec.containers[0] as $c
  | "argv_overridden=\((($c.command // []) + ($c.args // [])) | length > 0)"
    + " secret_env=\([($c.env // [])[] | select(.valueFrom.secretKeyRef) | .name] | join(","))"
    + " run_as_user=\(.items[0].spec.securityContext.runAsUser)"
    + " image_id=\(.items[0].status.containerStatuses[0].imageID)"'

restarts() {
  kube get pods -n "$NAMESPACE" -l app=mail -o json | jq '[.items[].status.containerStatuses[]?.restartCount] | add // 0'
}

job_state() {
  kube get job probe -n "$NAMESPACE" -o jsonpath='{.status.succeeded}/{.status.failed}' 2>/dev/null || true
}

# Run the probe Job; print its key=value output on one line.
run_probe() {
  local log_file=$1 deadline state
  kube apply -k "$MANIFESTS/probe" >>"$log_file" 2>&1 || return 1
  deadline=$(($(date +%s) + PROBE_TIMEOUT))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    state=$(job_state)
    case $state in
      1/* | */1)
        kube logs job/probe -n "$NAMESPACE" 2>>"$log_file" | grep -E '^[a-z_]+=' | tr '\n' ' '
        return 0
        ;;
    esac
    sleep 1
  done
  return 1
}

probe_value() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -n 1; }

record_load() {
  local opt=$1 phase=$2 loadavg total
  loadavg=$(uptime | sed -e 's/.*load average[s]*: //' -e 's/,//g')
  total=$(docker ps -q | wc -l | tr -d ' ')
  tsv load.tsv "$(utc_now)" "$opt" "$phase" "$loadavg" "$total"
}

to_mib_awk='function to_mib(v,  n, u) {
  n = v; sub(/[A-Za-z]+$/, "", n); u = v; sub(/^[0-9.]+/, "", u)
  if (u == "B") return n / 1048576
  if (u == "KiB" || u == "kB") return n / 1024
  if (u == "MiB" || u == "MB") return n
  if (u == "GiB" || u == "GB") return n * 1024
  return -1 }'

# One sample: working set and CPU of the option's pod (kubelet Summary API),
# and the whole node container (docker stats).
# Prints "pod_mem_mib<TAB>pod_cpu_pct<TAB>node_mem_mib<TAB>node_cpu_pct".
idle_sample() {
  local opt=$1 run=$2 sample=$3 summary pod node_stats
  summary=$(kube get --raw "/api/v1/nodes/$NODE/proxy/stats/summary") || die "summary API unreachable"
  pod=$(printf '%s' "$summary" | jq -r --arg ns "$NAMESPACE" '
    [.pods[] | select(.podRef.namespace == $ns and (.podRef.name | startswith("mail-")))
     | [((.memory.workingSetBytes // 0) / 1048576), ((.cpu.usageNanoCores // 0) / 10000000)]]
    | if length == 0 then "0\t0" else (map(.[0]) | add | tostring) + "\t" + (map(.[1]) | add | tostring) end')
  node_stats=$(docker stats --no-stream --format '{{.CPUPerc}}\t{{.MemUsage}}' "$NODE" |
    awk -F'\t' "$to_mib_awk"'{ cpu = $1; sub(/%/, "", cpu); split($2, m, " "); printf "%.1f\t%.2f", to_mib(m[1]), cpu }')
  printf '%s\t%s\n' "$pod" "$node_stats" | awk -F'\t' -v o="$opt" -v r="$run" -v s="$sample" \
    '{ printf "%s\t%s\t%s\t%.1f\t%.2f\t%s\t%s\n", o, r, s, $1, $2, $3, $4 }' >>"$TRIAL_DIR/idle.tsv"
  printf '%s\t%s\n' "$pod" "$node_stats" | awk -F'\t' '{ printf "%.1f\t%.2f\t%s\t%s\n", $1, $2, $3, $4 }'
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

# Why the server did not become ready: pod states, warnings, PodSecurity.
record_failure() {
  local opt=$1 log_file=$2 reasons
  kube get pods -n "$NAMESPACE" -o wide >>"$log_file" 2>&1 || true
  kube logs deployment/mail -n "$NAMESPACE" --tail=50 >>"$log_file" 2>&1 || true
  kube get events -n "$NAMESPACE" -o wide >>"$log_file" 2>&1 || true
  reasons=$(kube get events -n "$NAMESPACE" --field-selector type=Warning -o json 2>/dev/null |
    jq -r '[.items[] | .message | .[0:200]] | unique | .[0:3] | join(" || ")' 2>/dev/null || true)
  tsv functional.tsv "$opt" install-ready no "${reasons:-see $log_file}"
}

# --- One run --------------------------------------------------------------------

timed_run() {
  local opt=$1 run=$2 log_file started t_create t_cluster t0 t1 t_ready ready_s
  local restricted out spec secret probe send noauth auth found samples="" i sample
  local mem cpu node_mem node_cpu arch
  log_file="$LOGS/$opt-run-$run.log"
  record_load "$opt" "run-$run"
  started=$(utc_now)
  log "$opt run $run: create cluster"
  t_create=$(now)
  create_cluster >"$log_file" 2>&1 || die "$opt run $run: kind create failed, see $log_file"
  t_cluster=$(wait_streak "$CLUSTER_TIMEOUT" cluster_ready) || die "$opt run $run: cluster not ready"
  arch=$(kube get node "$NODE" -o jsonpath='{.status.nodeInfo.architecture}')

  kube apply -f "$MANIFESTS/namespace.yaml" >>"$log_file" 2>&1 || die "$opt run $run: namespace rejected"
  create_secret >>"$log_file" 2>&1 || die "$opt run $run: Secret not created"
  secret=$(secret_check)

  log "$opt run $run: install $(option_version "$opt")"
  t0=$(now)
  out=$(kube apply -k "$MANIFESTS/$opt" 2>&1) || {
    printf '%s\n' "$out" >>"$log_file"
    die "$opt run $run: apply failed, see $log_file"
  }
  t1=$(now)
  printf '%s\n' "$out" >>"$log_file"
  restricted=yes
  if printf '%s' "$out" | grep -qi 'violate PodSecurity'; then restricted=warned; fi

  if [ "$opt" = none ]; then
    t_ready=$t1
  elif ! t_ready=$(wait_streak "$INSTALL_TIMEOUT" mail_ready); then
    log "$opt run $run: not ready after ${INSTALL_TIMEOUT}s"
    record_failure "$opt" "$log_file"
    record_pulls "$opt" "$run"
    tsv runs.tsv "$opt" "$run" "$started" "$(seconds_between "$t_create" "$t_cluster")" \
      "$(seconds_between "$t0" "$t1")" not-ready unknown - - - - - - - - "$arch"
    delete_cluster >>"$log_file" 2>&1 || die "$opt run $run: delete failed"
    RUN_OK=0
    return 0
  fi
  ready_s=$(seconds_between "$t0" "$t_ready")
  log "$opt run $run: ready in $ready_s s"

  spec=-
  if [ "$opt" != none ]; then
    spec=$(kube get pods -n "$NAMESPACE" -l app=mail -o json | jq -r "$SPEC_CHECK")
  fi
  tsv functional.tsv "$opt" "run-$run" spec "$spec $secret restricted=$restricted node_arch=$arch"

  probe=$(run_probe "$log_file") || probe="probe=timeout"
  tsv functional.tsv "$opt" "run-$run" probe "$probe"
  send=$(probe_value "$probe" send_to_api_s)
  noauth=$(probe_value "$probe" noauth_status)
  auth=$(probe_value "$probe" auth_status)
  found=$(probe_value "$probe" found)
  log "$opt run $run: probe $probe"

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

  record_pulls "$opt" "$run"
  local nrestarts=0
  if [ "$opt" != none ]; then nrestarts=$(restarts); fi
  tsv runs.tsv "$opt" "$run" "$started" "$(seconds_between "$t_create" "$t_cluster")" \
    "$(seconds_between "$t0" "$t1")" "$ready_s" "$restricted" "${send:--}" "${noauth:--}" \
    "${auth:--}" "${found:--}" "$mem" "$cpu" "$node_mem" "$node_cpu" "$nrestarts" "$arch"
  log "$opt run $run: delete cluster"
  delete_cluster >>"$log_file" 2>&1 || die "$opt run $run: delete failed"
}

# --- Start-up checks --------------------------------------------------------------

check_versions() {
  local v
  for v in docker kind kubectl jq shasum awk zsh; do
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
  tsv versions.tsv node-image "$KIND_IMAGE"
  tsv versions.tsv docker "$(docker version --format '{{.Server.Version}}')"
  tsv versions.tsv engine "$(docker info --format '{{.OperatingSystem}} {{.Architecture}} {{.NCPU}} CPU {{.MemTotal}} B cgroup v{{.CgroupVersion}}')"
  tsv versions.tsv host "$(sysctl -n hw.model 2>/dev/null || uname -m) $(sw_vers -productVersion 2>/dev/null || uname -r)"
  tsv versions.tsv kind-network-before "$(docker network inspect kind >/dev/null 2>&1 && echo present || echo absent)"
  tsv versions.tsv probe "$PROBE_IMAGE"
  for v in $OPTIONS; do
    case $v in
      mailpit | maildev | smtp4dev) tsv versions.tsv "$v" "$(option_field "$v" 2)" ;;
      none) tsv versions.tsv none - ;;
      *) die "unknown option: $v" ;;
    esac
  done
}

acquire_lock() {
  [ -n "$BENCH_LOCK" ] || return 0
  if ! mkdir "$BENCH_LOCK" 2>/dev/null; then
    echo "lock $BENCH_LOCK is held: $(cat "$BENCH_LOCK/owner" 2>/dev/null || echo unknown owner)" >&2
    exit 75
  fi
  LOCK_HELD=1
  printf 'BENCH-013 %s pid %s\n' "$(utc_now)" "$$" >"$BENCH_LOCK/owner"
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
  release_lock
  log "results in $TRIAL_DIR"
  exit "$rc"
}

# --- Summary ----------------------------------------------------------------------

summarize() {
  local opt column name values
  tsv summary.tsv option metric runs values median range
  for opt in $OPTIONS; do
    for column in 6:ready_s 8:send_to_api_s 12:pod_mem_mib 13:pod_cpu_pct 14:node_mem_mib 15:node_cpu_pct 4:cluster_s; do
      name=${column#*:}
      values=$(awk -F'\t' -v o="$opt" -v c="${column%%:*}" \
        '$1 == o && $2 != "run" && $c ~ /^[0-9.]+$/ { print $c }' "$TRIAL_DIR/runs.tsv")
      tsv summary.tsv "$opt" "$name" "$(printf '%s\n' "$values" | grep -c . || true)" \
        "$(printf '%s\n' "$values" | paste -sd, -)" "$(printf '%s\n' "$values" | grep . | median_range)"
    done
  done
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

  tsv versions.tsv item version
  tsv manifests.tsv file sha256
  tsv images.tsv option image compressed_bytes tag_platforms
  tsv runs.tsv option run started_utc cluster_s apply_s ready_s restricted send_to_api_s \
    noauth_status auth_status found pod_mem_mib pod_cpu_pct node_mem_mib node_cpu_pct restarts node_arch
  tsv functional.tsv option run check result
  tsv idle.tsv option run sample pod_mem_mib pod_cpu_pct node_mem_mib node_cpu_pct
  tsv node-images.tsv option run status image took
  tsv load.tsv utc option phase loadavg_1_5_15 running_containers

  # The manifest check needs no engine. Every docker, kind and kubectl command
  # comes after the lock; until the cluster check passes, the EXIT trap only
  # releases the lock, so a refusal deletes nothing.
  verify_manifests
  acquire_lock
  trap release_lock EXIT
  check_versions
  cluster_exists && die "a kind cluster named $CLUSTER already exists"
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  log "trial directory: $TRIAL_DIR"
  verify_images

  run=1
  while [ "$run" -le "$RUNS" ]; do
    for opt in $OPTIONS; do
      if is_skipped "$opt"; then continue; fi
      # Called outside any "if", so that set -e stays active inside.
      RUN_OK=1
      timed_run "$opt" "$run"
      if [ "$RUN_OK" = 0 ]; then
        SKIPPED="$SKIPPED $opt"
        log "$opt: not ready, remaining runs skipped"
      fi
      sleep "$PAUSE_BETWEEN_RUNS"
    done
    run=$((run + 1))
  done
  summarize
  column -t -s "$(printf '\t')" "$TRIAL_DIR/summary.tsv" >&2 || true
}

main "$@"
