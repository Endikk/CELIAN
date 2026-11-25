#!/usr/bin/env bash
# BENCH-005: the tool behind `task up` in the generated project, on the PC.
# Options:
#   tilt     kind cluster, then Tilt builds the API and the front, loads them
#            into kind and applies the Kubernetes manifests of the stack;
#   compose  Docker Compose, the same stack without Kubernetes;
#   aspire   Aspire AppHost: the API as a .NET process on the host, the rest
#            in containers;
#   kubectl  O4, no loop tool: kind cluster, docker build, kind load, and
#            kubectl apply -k on the same manifests as Tilt;
#   aspirek8s  Aspire on kind: `aspire publish` turns the AppHost of
#            stack/aspire-k8s into a Helm chart, docker build and kind load
#            the API and front images, helm upgrade --install the chart.
# For kubectl and aspirek8s, the development loop rebuilds, loads and
# applies again after each change, as the developer would.
# The stack (tests/bench/bench-005/stack) is an API with a health endpoint, a
# static front, Postgres, Valkey, and a busybox probe that prints, every half
# second, what the API and the front answer from inside the environment.
#
# For each option the script measures, one cold run (stack images removed by
# exact reference, empty NuGet cache for Aspire) then RUNS warm runs:
#   - `task up` time: from the first command until a probe line shows the API
#     and the front answering with this run's markers, and Postgres and the
#     cache accepting connections;
#   - memory and CPU at rest, IDLE_WAIT seconds after "ready": containers of
#     the option (docker stats) plus the host processes the tool leaves
#     running (ps), 3 samples 10 s apart;
#   - memory peak during `task up`, sampled every second or so;
#   - `task down` time, until no container of the option is left;
#   - images pulled by the kind node (Pulled events) and by Docker (pull
#     events) during the run.
# In warm run 1, the development loop: LOOP_ITER edits of the front's static
# file, then of the API's source, each timed until the probe sees the change.
# For Tilt, once: the kind cluster alone at rest, for the US-005 profiles.
#
# Usage: tests/bench/bench-005-orchestration.sh [TRIAL_DIR]
#   TRIAL_DIR, if given, must be missing or empty (default: a new mktemp -d).
#   Environment:
#     OPTIONS="tilt compose aspire"  options, measured in this order
#     RUNS=3          warm runs per option, after the cold run
#     COLD=1          add a cold run first; 0 to skip it
#     COLD_REMOVE=1   0: the first run keeps the cached images (warm-up)
#     IDLE_WAIT=120   seconds between "ready" and the first idle sample
#     LOOP_ITER=3     development loop edits per kind of change; 0 to skip
#     CLUSTER_IDLE=1  measure the kind cluster alone (Tilt); 0 to skip
#     ASPIRE_BIN=aspire  path of the Aspire CLI
#     TILT_PORT=10355    port of Tilt's web server, on 127.0.0.1
#     BENCH_LOCK=     if set, a directory used as a lock shared with other
#                     benchmarks: created before the first measure, removed
#                     at exit. Waits while another owner holds it; a lock
#                     older than 90 minutes is stale and removed, with a log.
#                     Refreshed at each timed run while held.
#   Results (TSV) in TRIAL_DIR: versions.tsv, load.tsv, runs.tsv,
#   idle-samples.tsv, peak-samples.tsv, loop.tsv, cluster-idle.tsv,
#   ports.tsv, pulls.tsv, images.tsv, leftovers.tsv, summary.tsv; command
#   output in TRIAL_DIR/logs/.
# Needs: bash >= 3.2, docker with compose, kubectl (1.35 to 1.37), jq, perl,
#   lsof, shasum, openssl, and the options measured at the versions pinned
#   below: tilt and kind; docker compose; dotnet and the Aspire CLI; helm
#   for aspirek8s.
#
# Safety:
#   - every container, cluster and Compose project is named celian-bench-005.
#     The script refuses to start if one exists, or if a port it needs is in
#     use. Its EXIT trap is set only after these checks, after the lock and
#     after the inventory of what exists (kind network, images, build
#     outputs), so a refusal deletes nothing; afterwards it deletes only
#     what it created, with each tool's own command;
#   - umask 077; KUBECONFIG, NUGET_PACKAGES and the env files with the
#     generated passwords live in TRIAL_DIR; ~/.kube is not used;
#   - images are removed by exact reference only, never with --force, and
#     never an image that was present before the script started;
#   - no curl, no `docker run`, no `docker exec`: HTTP is tested by the probe,
#     inside the environment, and read from its logs.
# Side effects outside TRIAL_DIR, listed in leftovers.tsv: the Docker image
# and build caches (pinned images stay cached at the end, built images are
# removed); the "kind" network, removed at the end if the script created it
# and nothing uses it; ~/.tilt-dev and ~/.aspire, the state of Tilt and of
# the Aspire CLI; the build output of the AppHost under the dotnet runfile
# directory, removed at the end when the script created it.
#
# One file above the usual 800-line ceiling, on purpose: the script is run on
# its own, by hand or by a reviewer, and must stay readable and copyable
# without a library next to it.
set -euo pipefail
umask 077

# --- Pinned versions ----------------------------------------------------------

readonly TILT_VERSION="v0.37.9"
readonly KIND_VERSION="v0.33.0"
readonly COMPOSE_VERSION="5.5.0"
readonly DOTNET_SDK_VERSION="10.0.401"
readonly ASPIRE_VERSION="17.0.0"
readonly HELM_VERSION="v4.3.2"
# Image the Aspire Kubernetes chart adds for its dashboard, by tag (M12).
readonly ASPIRE_DASHBOARD_IMAGE="mcr.microsoft.com/aspire/nightly/dashboard:17.0"
readonly KUBECTL_MINORS="35 36 37"

# Images, pinned by digest (read on 2026-11-19). The same references are in
# the stack files; check_stack_pins fails if they drift apart.
readonly KIND_IMAGE="kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed"
readonly SDK_IMAGE="mcr.microsoft.com/dotnet/sdk:10.0.404@sha256:bef136a371963aaa46ec97882845ef6f54dec15728bb4b128b1c2a400ffbc9b4"
readonly ASPNET_IMAGE="mcr.microsoft.com/dotnet/aspnet:10.0.15@sha256:12b1135f5f8b3c0a214f2a680ff2033dff4f684f445d6c697d9524ceeb303586"
readonly NGINX_IMAGE="nginx:1.30.7-alpine@sha256:bef154735288bc38d99fac41ae63730684bcc661503673a04a0f9bc526ba8598"
readonly BUSYBOX_IMAGE="busybox:1.37.0@sha256:a7dbc319b1438115a207e11930dc4bb3e643dcb3ec0bdd694bb36cd8fad289ec"
readonly POSTGRES_IMAGE="postgres:18.7-alpine@sha256:ff64c9e3bdf8e2120107d3559de8db314e8305f7e38c5105903c6295876738ff"
readonly VALKEY_IMAGE="valkey/valkey:9.1.4-alpine@sha256:56729e68bdda139cbd3f6a2538683dc3523325fc5711ea1a379938f1b37893f0"
# Not ours to pin: Aspire 17.0.0's DCP pulls this base by tag to build its
# network tunnel image (dcptun_*), seen in the smoke test of 2026-11-19.
readonly AZURELINUX_IMAGE="mcr.microsoft.com/azurelinux/base/core:3.0"

readonly NAME="celian-bench-005"
readonly KUBE_CONTEXT="kind-$NAME"
readonly API_PORT=18580
readonly FRONT_PORT=18581
# Ports of the Aspire launch profile (stack/aspire/apphost.run.json).
readonly ASPIRE_PORTS="15162 19210 20277"
readonly SAMPLES=3
readonly SAMPLE_GAP=10
readonly PAUSE_BETWEEN_RUNS=15
readonly READY_TIMEOUT=900
readonly LOOP_TIMEOUT=600
readonly LOCK_STALE_MIN=90
readonly LOCK_RETRY=120

OPTIONS="${OPTIONS:-tilt compose aspire}"
RUNS="${RUNS:-3}"
COLD="${COLD:-1}"
# 0: run 0 keeps the cached images, as a warm-up excluded from the medians.
COLD_REMOVE="${COLD_REMOVE:-1}"
IDLE_WAIT="${IDLE_WAIT:-120}"
LOOP_ITER="${LOOP_ITER:-3}"
CLUSTER_IDLE="${CLUSTER_IDLE:-1}"
ASPIRE_BIN="${ASPIRE_BIN:-aspire}"
TILT_PORT="${TILT_PORT:-10355}"
BENCH_LOCK="${BENCH_LOCK:-}"
readonly OPTIONS RUNS COLD COLD_REMOVE IDLE_WAIT LOOP_ITER CLUSTER_IDLE ASPIRE_BIN TILT_PORT BENCH_LOCK

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
readonly STACK="$SCRIPT_DIR/bench-005/stack"
readonly RUNFILE_DIR="$HOME/Library/Application Support/dotnet/runfile"

TRIAL_DIR=""
LOGS=""
WORK=""
TOOL_PID=""
LOCK_HELD=0
LOCK_TAKEN=""
KIND_NETWORK_EXISTED=0
PREEXISTING_IMAGES=""
RUNFILE_MATCH=""
ASPIRE_MATCH=""
PEAK_PID=""
DCPTUN_PREEXISTING=0
API_TAG=""
FRONT_TAG=""

# --- Helpers ------------------------------------------------------------------

log() { printf '[bench-005 %s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die() {
  log "ERROR: $*"
  exit 1
}
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
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

# kubectl on this script's cluster only, whatever the current context.
kube() { kubectl --context "$KUBE_CONTEXT" --request-timeout=10s "$@"; }

# --- Lock shared with the other benchmarks -----------------------------------

lock_age_min() {
  local mtime
  mtime=$(stat -c %Y "$BENCH_LOCK" 2>/dev/null || stat -f %m "$BENCH_LOCK" 2>/dev/null || echo 0)
  echo $((($(date +%s) - mtime) / 60))
}

acquire_lock() {
  local age owner
  [ -n "$BENCH_LOCK" ] || return 0
  while ! mkdir "$BENCH_LOCK" 2>/dev/null; do
    owner=$(cat "$BENCH_LOCK/owner" 2>/dev/null || echo unknown)
    age=$(lock_age_min)
    if [ "$age" -ge "$LOCK_STALE_MIN" ]; then
      log "lock $BENCH_LOCK is stale (${age} min, owner: $owner): removed"
      rm -rf "$BENCH_LOCK"
      continue
    fi
    log "lock held by '$owner' for ${age} min, retry in ${LOCK_RETRY} s"
    sleep "$LOCK_RETRY"
  done
  LOCK_TAKEN=$(utc_now)
  printf 'BENCH-005 %s\n' "$LOCK_TAKEN" >"$BENCH_LOCK/owner"
  LOCK_HELD=1
  log "lock $BENCH_LOCK taken"
}

# Called at each timed run: the lock is stale after LOCK_STALE_MIN minutes,
# and a series of several options can last longer. The owner file is
# replaced (new directory entry) and the directory touched, so that both
# the file and the directory show a fresh date.
refresh_lock() {
  [ "$LOCK_HELD" = 1 ] || return 0
  grep -q '^BENCH-005 ' "$BENCH_LOCK/owner" 2>/dev/null || return 0
  printf 'BENCH-005 %s (series started %s)\n' "$(utc_now)" "$LOCK_TAKEN" >"$BENCH_LOCK/owner.new"
  mv "$BENCH_LOCK/owner.new" "$BENCH_LOCK/owner"
  touch "$BENCH_LOCK"
}

release_lock() {
  if [ "$LOCK_HELD" = 1 ] && grep -q '^BENCH-005 ' "$BENCH_LOCK/owner" 2>/dev/null; then
    rm -rf "$BENCH_LOCK"
    log "lock $BENCH_LOCK released"
  fi
  LOCK_HELD=0
}

# --- Images -------------------------------------------------------------------

option_images() {
  case $1 in
    tilt | compose | kubectl | aspirek8s)
      printf '%s\n' "$SDK_IMAGE" "$ASPNET_IMAGE" "$NGINX_IMAGE" "$BUSYBOX_IMAGE" \
        "$POSTGRES_IMAGE" "$VALKEY_IMAGE"
      ;;
    aspire)
      printf '%s\n' "$NGINX_IMAGE" "$BUSYBOX_IMAGE" "$POSTGRES_IMAGE" "$VALKEY_IMAGE" \
        "$AZURELINUX_IMAGE"
      ;;
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

image_remove() {
  local ref=$1 variant
  case " $PREEXISTING_IMAGES " in
    *" $ref "*)
      log "$ref was present before the script started: left in place"
      return 0
      ;;
  esac
  for variant in $(image_ref_variants "$ref"); do
    if docker image inspect "$variant" >/dev/null 2>&1; then
      docker image rm "$variant" >>"$LOGS/images.log" 2>&1 ||
        log "could not remove $variant (in use?), left in place"
    fi
  done
}

# Images built by this script: Tilt's celian-bench-005/{api,front} and
# Compose's celian-bench-005-{api,front}, every tag.
built_images() {
  docker images --format '{{.Repository}}:{{.Tag}}' |
    grep -E "^$NAME(/|-)(api|front):" || true
  # DCP's tunnel image, built during the run, unless it was there before.
  if [ "$DCPTUN_PREEXISTING" = 0 ]; then dcptun_images; fi
}

remove_built_images() {
  local ref
  for ref in $(built_images); do
    docker image rm "$ref" >>"$LOGS/images.log" 2>&1 || log "could not remove $ref"
  done
}

# cold: no image of the option present; warm: all; partial otherwise.
cache_state() {
  local opt=$1 ref present=0 total=0
  for ref in $(option_images "$opt"); do
    total=$((total + 1))
    if image_present "$ref"; then present=$((present + 1)); fi
  done
  if [ "$present" -eq 0 ]; then
    echo cold
  elif [ "$present" -eq "$total" ]; then
    echo warm
  else
    echo partial
  fi
}

# Compressed size per architecture (layers plus config), read from the
# registry with docker manifest inspect: no pull, no container.
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
  local ref size
  for ref in "$KIND_IMAGE" "$SDK_IMAGE" "$ASPNET_IMAGE" "$NGINX_IMAGE" "$BUSYBOX_IMAGE" \
    "$POSTGRES_IMAGE" "$VALKEY_IMAGE" "$AZURELINUX_IMAGE" "$ASPIRE_DASHBOARD_IMAGE"; do
    size="-"
    if image_present "$ref"; then
      size=$(docker image inspect --format '{{.Size}}' "$(image_ref_variants "$ref" | tail -1)" 2>/dev/null ||
        docker image inspect --format '{{.Size}}' "$(image_ref_variants "$ref" | head -1)")
    fi
    tsv images.tsv "$ref" "$size" "$(registry_sizes "$ref")"
  done
}

# Compressed volume of the NuGet packages restored for the AppHost: one
# canonical <id>.<version>.nupkg per package directory.
record_nuget() {
  local dir="$TRIAL_DIR/nuget" phase=$1 count bytes
  [ -d "$dir" ] || return 0
  count=0
  bytes=0
  while IFS= read -r f; do
    count=$((count + 1))
    bytes=$((bytes + $(stat -c %s "$f" 2>/dev/null || stat -f %z "$f")))
  done < <(find "$dir" -mindepth 3 -maxdepth 3 -name '*.nupkg' | awk -F/ '{
    id = $(NF - 2); ver = $(NF - 1); if ($NF == id "." ver ".nupkg") print }')
  tsv images.tsv "nuget:$phase" "$(du -sk "$dir" | awk '{ print $1 * 1024 }')" "nupkg=$bytes,packages=$count"
}

# --- Containers and host processes of the option ------------------------------

# Containers of the option: named celian-bench-005*, plus the network tunnel
# that Aspire's DCP starts from its own image (dcptun_*) when a container
# reaches a process on the host.
my_containers() { list_containers -a; }
my_running() { list_containers; }

list_containers() {
  local image
  {
    docker ps "$@" --filter "name=$NAME" --format '{{.Names}}'
    for image in $(dcptun_images); do
      docker ps "$@" --filter "ancestor=$image" --format '{{.Names}}' 2>/dev/null || true
    done
  } | sort -u
}

dcptun_images() {
  docker images --format '{{.Repository}}:{{.Tag}}' | grep '^dcptun_' || true
}

# Host processes the tool leaves running: descendants of TOOL_PID, plus any
# process whose command line names the trial directory, the AppHost build
# output (RUNFILE_MATCH) or the Aspire CLI's own directory (ASPIRE_MATCH).
# The script itself and its helpers are excluded.
owned_pids() {
  local snapshot
  snapshot=$(ps -axwwo pid=,ppid=,command=)
  # "$TRIAL_DIR/", with the slash: a file inside the trial directory, not a
  # neighbour that shares its prefix. Shells are left out: the script's
  # caller may name the trial directory in its own command line.
  printf '%s\n' "$snapshot" | awk -v root="${TOOL_PID:-0}" -v trial="$TRIAL_DIR/" \
    -v runfile="${RUNFILE_MATCH:-/nonexistent/}" -v cli="${ASPIRE_MATCH:-/nonexistent/}" -v self="$$" '
    { pid = $1; ppid = $2; cmd = $0; sub(/^ *[0-9]+ +[0-9]+ +/, "", cmd)
      parent[pid] = ppid; command[pid] = cmd; order[NR] = pid }
    END {
      for (i = 1; i <= NR; i++) {
        p = order[i]; c = command[p]; mine = 0
        if (index(c, "bench-005-orchestration.sh") || p == self) continue
        if (c ~ /^([^ ]*\/)?(ps|awk|sleep|sort|grep|sed|cat|perl|date|lsof)( |$)/) continue
        if (c ~ /^([^ ]*\/)?(sh|bash|zsh) -c /) continue
        if (index(c, trial) || index(c, runfile) || index(c, cli)) mine = 1
        q = p
        for (d = 0; d < 50 && q > 1 && !mine; d++) { if (q == root) mine = 1; q = parent[q] }
        if (mine) print p
      }
    }'
}

to_mib_awk='function to_mib(v,  n, u) {
  n = v; sub(/[A-Za-z]+$/, "", n); u = v; sub(/^[0-9.]+/, "", u)
  if (u == "B") return n / 1048576
  if (u == "KiB" || u == "kB") return n / 1024
  if (u == "MiB" || u == "MB") return n
  if (u == "GiB" || u == "GB") return n * 1024
  return -1 }'

# One sample: prints "cont_mib<TAB>cont_cpu<TAB>host_mib<TAB>host_cpu".
# With a file argument, the detail per container and per process goes there.
sample() {
  local detail=${1:-/dev/null} names pids stats cont host
  read -r -a names <<<"$(my_running | tr '\n' ' ')"
  cont="0.0	0.00"
  if [ "${#names[@]}" -gt 0 ]; then
    stats=$(docker stats --no-stream --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' "${names[@]}" 2>/dev/null || true)
    cont=$(printf '%s\n' "$stats" | awk -F'\t' -v out="$detail" "$to_mib_awk"'
      NF >= 3 { cpu = $2; sub(/%/, "", cpu); split($3, m, " "); mib = to_mib(m[1])
        printf "container\t%s\t%.2f\t%.1f\n", $1, cpu, mib >> out; tc += cpu; tm += mib }
      END { printf "%.1f\t%.2f\n", tm, tc }')
  fi
  pids=$(owned_pids | paste -sd, -)
  host="0.0	0.00"
  if [ -n "$pids" ]; then
    # A process may exit between the two ps calls: ps then fails for it only.
    host=$({ ps -o pid=,rss=,%cpu=,comm= -p "$pids" 2>/dev/null || true; } | awk -v out="$detail" '
      { printf "process\t%s:%s\t%.2f\t%.1f\n", $1, $4, $3, $2 / 1024 >> out; tm += $2 / 1024; tc += $3 }
      END { printf "%.1f\t%.2f\n", tm, tc }')
  fi
  printf '%s\t%s\n' "$(printf '%s' "$cont" | cut -f1-2)" "$(printf '%s' "$host" | cut -f1-2)"
}

# Background sampler for the memory peak during `task up`.
start_peak_sampler() {
  local opt=$1 run=$2 stop=$3
  (
    while [ ! -f "$stop" ]; do
      tsv peak-samples.tsv "$opt" "$run" "$(utc_now)" "$(sample)"
      sleep 1
    done
  ) &
  PEAK_PID=$!
}

# --- The probe ----------------------------------------------------------------

probe_line() {
  case $1 in
    tilt | kubectl) kube logs deploy/probe --tail=1 2>/dev/null || true ;;
    aspirek8s) kube logs deploy/probe-deployment --tail=1 2>/dev/null || true ;;
    compose | aspire)
      local c
      c=$(docker ps --filter "name=$NAME-probe" --format '{{.Names}}' | head -1)
      [ -n "$c" ] && docker logs --tail 1 "$c" 2>&1 || true
      ;;
  esac
}

line_matches() {
  local line=$1 api=$2 front=$3
  case $line in *"api=[ok $api]"*) ;; *) return 1 ;; esac
  case $line in *"front=[$front]"*) ;; *) return 1 ;; esac
  case $line in *"pg=[ok]"*) ;; *) return 1 ;; esac
  case $line in *"cache=[]"*) return 1 ;; *"cache=["*) return 0 ;; *) return 1 ;; esac
}

# Prints the time of the first probe line showing both markers.
wait_markers() {
  local opt=$1 api=$2 front=$3 timeout=$4 deadline line t
  deadline=$(($(date +%s) + timeout))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    t=$(now)
    line=$(probe_line "$opt")
    if line_matches "$line" "$api" "$front"; then
      echo "$t"
      return 0
    fi
    sleep 0.5
  done
  log "$opt: last probe line: ${line:-none}"
  return 1
}

# --- Stack copy and markers ---------------------------------------------------

prepare_work() {
  local opt=$1
  WORK="$TRIAL_DIR/work/$opt"
  if [ ! -d "$WORK" ]; then
    mkdir -p "$WORK"
    cp -R "$STACK/." "$WORK/"
    # umask 077 would hide them from nginx and from the probe.
    chmod -R go+rX "$WORK/front" "$WORK/probe.sh"
  fi
}

# Build output directories of file-based apps (the AppHost), by name.
runfile_dirs() {
  if [ -d "$RUNFILE_DIR" ]; then
    find "$RUNFILE_DIR" -mindepth 1 -maxdepth 1 -type d -name 'apphost-*' -exec basename {} \; | sort
  fi
}

new_runfile_dirs() {
  runfile_dirs | comm -13 "$TRIAL_DIR/runfile-before.txt" -
}

set_api_marker() {
  printf 'namespace Api;\n\ninternal static class Marker\n{\n    public const string Value = "%s";\n}\n' \
    "$2" >"$1/api/Marker.cs"
}

set_front_marker() {
  printf '<!doctype html>\n<html lang="fr">\n<head><meta charset="utf-8"><title>BENCH-005</title></head>\n<body><p>%s</p></body>\n</html>\n' \
    "$2" >"$1/front/html/index.html.tmp"
  chmod 644 "$1/front/html/index.html.tmp"
  mv "$1/front/html/index.html.tmp" "$1/front/html/index.html"
}

# --- Up and down, per option --------------------------------------------------

up_tilt() {
  local run=$1
  kind create cluster --name "$NAME" --image "$KIND_IMAGE" --config "$WORK/kind.yaml" \
    --kubeconfig "$KUBECONFIG" >>"$LOGS/tilt-$run.log" 2>&1 || die "kind create failed"
  kube create secret generic pg-auth --from-file=password="$TRIAL_DIR/pg-password" >>"$LOGS/tilt-$run.log" 2>&1
  kube create configmap probe-script --from-file=probe.sh="$WORK/probe.sh" >>"$LOGS/tilt-$run.log" 2>&1
  tilt up --file "$WORK/Tiltfile" --host 127.0.0.1 --port "$TILT_PORT" --stream \
    >>"$LOGS/tilt-$run.log" 2>&1 &
  TOOL_PID=$!
}

up_compose() {
  local run=$1
  docker compose -p "$NAME" -f "$WORK/compose.yaml" --env-file "$TRIAL_DIR/compose.env" \
    up --build --watch >>"$LOGS/compose-$run.log" 2>&1 &
  TOOL_PID=$!
}

up_aspire() {
  local run=$1 pid
  (
    cd "$WORK/aspire"
    # shellcheck disable=SC1091 # generated at run time
    . "$TRIAL_DIR/aspire.env"
    "$ASPIRE_BIN" start --apphost apphost.cs --launch-profile http --non-interactive --nologo
  ) >>"$LOGS/aspire-$run.log" 2>&1 || die "aspire start failed, see $LOGS/aspire-$run.log"
  RUNFILE_MATCH="$RUNFILE_DIR/$(new_runfile_dirs | head -1)/"
  # The AppHost process, root of the processes counted for Aspire.
  "$ASPIRE_BIN" ps --format Json --nologo >"$LOGS/aspire-ps-$run.json" 2>&1 || true
  pid=$(jq -r --arg d "$WORK/aspire" '[.[]? | select((.path // .appHostPath // "") | startswith($d)) |
      (.pid // .appHostPid // .processId)] | first // empty' "$LOGS/aspire-ps-$run.json" 2>/dev/null || true)
  TOOL_PID=${pid:-}
}

down_tilt() {
  local run=$1
  if [ -n "$TOOL_PID" ]; then
    kill -INT "$TOOL_PID" 2>/dev/null || true
    wait "$TOOL_PID" 2>/dev/null || true
  fi
  kind delete cluster --name "$NAME" --kubeconfig "$KUBECONFIG" >>"$LOGS/tilt-$run.log" 2>&1
}

down_compose() {
  local run=$1
  if [ -n "$TOOL_PID" ]; then
    kill -INT "$TOOL_PID" 2>/dev/null || true
    wait "$TOOL_PID" 2>/dev/null || true
  fi
  docker compose -p "$NAME" -f "$WORK/compose.yaml" --env-file "$TRIAL_DIR/compose.env" \
    down --remove-orphans -v >>"$LOGS/compose-$run.log" 2>&1
}

# --- O4 (kubectl) and Aspire on kind (aspirek8s): build, kind load, apply ----

create_kind() {
  local log_file=$1
  kind create cluster --name "$NAME" --image "$KIND_IMAGE" --config "$WORK/kind.yaml" \
    --kubeconfig "$KUBECONFIG" >>"$log_file" 2>&1 || die "kind create failed, see $log_file"
}

# Build one image of the stack under a new tag and load it into kind.
build_load() {
  local component=$1 log_file=$2 tag
  tag="b$(date +%s)$RANDOM"
  docker build -q -t "$NAME/$component:$tag" "$WORK/$component" >>"$log_file" 2>&1 ||
    die "docker build $component failed, see $log_file"
  kind load docker-image "$NAME/$component:$tag" --name "$NAME" >>"$log_file" 2>&1 ||
    die "kind load $component failed, see $log_file"
  case $component in
    api) API_TAG=$tag ;;
    front) FRONT_TAG=$tag ;;
  esac
}

# O4: the same manifests as Tilt, with the image tags set by kustomize.
apply_kubectl() {
  local log_file=$1 f
  {
    printf 'apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nresources:\n'
    for f in "$WORK"/k8s/app/*.yaml "$WORK"/k8s/local/*.yaml "$WORK"/k8s/bench/*.yaml; do
      printf '  - %s\n' "${f#"$WORK"/k8s/}"
    done
    printf 'images:\n  - name: %s/api\n    newTag: "%s"\n  - name: %s/front\n    newTag: "%s"\n' \
      "$NAME" "$API_TAG" "$NAME" "$FRONT_TAG"
  } >"$WORK/k8s/kustomization.yaml"
  kube apply -k "$WORK/k8s" >>"$log_file" 2>&1 || die "kubectl apply failed, see $log_file"
}

up_kubectl() {
  local log_file="$LOGS/kubectl-$1.log"
  create_kind "$log_file"
  kube create secret generic pg-auth --from-file=password="$TRIAL_DIR/pg-password" >>"$log_file" 2>&1
  kube create configmap probe-script --from-file=probe.sh="$WORK/probe.sh" >>"$log_file" 2>&1
  build_load api "$log_file"
  build_load front "$log_file"
  apply_kubectl "$log_file"
}

# Aspire on kind: the chart from `aspire publish`, installed by Helm with
# the images built by `task up` and the passwords of this trial.
apply_aspirek8s() {
  local log_file=$1
  printf 'parameters:\n  api:\n    port_http: 8080\n    api_image: "%s"\n  front:\n    front_image: "%s"\nsecrets:\n  postgres:\n    pgpassword: "%s"\n  valkey:\n    valkeypassword: "%s"\n' \
    "$NAME/api:$API_TAG" "$NAME/front:$FRONT_TAG" "$(cat "$TRIAL_DIR/pg-password")" \
    "$(cat "$TRIAL_DIR/valkey-password")" >"$TRIAL_DIR/helm-values.yaml"
  helm upgrade --install "$NAME" "$WORK/chart" -f "$TRIAL_DIR/helm-values.yaml" \
    --kube-context "$KUBE_CONTEXT" >>"$log_file" 2>&1 || die "helm upgrade failed, see $log_file"
}

up_aspirek8s() {
  local log_file="$LOGS/aspirek8s-$1.log"
  create_kind "$log_file"
  rm -rf "$WORK/chart"
  (
    cd "$WORK/aspire-k8s"
    # shellcheck disable=SC1091 # generated at run time
    . "$TRIAL_DIR/aspire.env"
    "$ASPIRE_BIN" publish --apphost apphost.cs -o "$WORK/chart" --non-interactive --nologo
  ) >>"$log_file" 2>&1 || die "aspire publish failed, see $log_file"
  build_load api "$log_file"
  build_load front "$log_file"
  apply_aspirek8s "$log_file"
}

down_kubectl() {
  kind delete cluster --name "$NAME" --kubeconfig "$KUBECONFIG" >>"$LOGS/kubectl-$1.log" 2>&1
}

down_aspirek8s() {
  kind delete cluster --name "$NAME" --kubeconfig "$KUBECONFIG" >>"$LOGS/aspirek8s-$1.log" 2>&1
}

# Development loop without a watcher: rebuild the changed image, load it,
# apply again. This is what the developer runs by hand (or through Task).
k8s_reload() {
  local opt=$1 component=$2 log_file="$LOGS/$1-loop.log"
  build_load "$component" "$log_file"
  case $opt in
    kubectl) apply_kubectl "$log_file" ;;
    aspirek8s) apply_aspirek8s "$log_file" ;;
  esac
}

down_aspire() {
  local run=$1
  "$ASPIRE_BIN" stop --apphost "$WORK/aspire/apphost.cs" --non-interactive --nologo \
    >>"$LOGS/aspire-$run.log" 2>&1 || true
}

# Waits until no container of the option is left, and no host process of the
# tool (at most 180 s). Only remaining containers are an error; remaining
# processes are recorded in leftovers.tsv.
wait_gone() {
  local phase=${1:-down} deadline pid
  deadline=$(($(date +%s) + 180))
  while [ -n "$(my_containers)" ] || [ -n "$(owned_pids)" ]; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      for pid in $(owned_pids); do
        tsv leftovers.tsv "-" "$phase" process "$pid:$(ps -o comm= -p "$pid" 2>/dev/null)" "left running"
      done
      [ -z "$(my_containers)" ]
      return
    fi
    sleep 0.5
  done
}

# --- Records ------------------------------------------------------------------

# Load average, this script's containers, and only a count of the others,
# plus the kind clusters and Compose projects of the other benchmarks
# (celian-bench-*), which share the Docker engine.
record_load() {
  local opt=$1 phase=$2 loadavg total mine others
  loadavg=$(uptime | sed -e 's/.*load average[s]*: //' -e 's/,//g')
  total=$(docker ps -q | wc -l | tr -d ' ')
  mine=$(my_running | grep -c . || true)
  others=$(
    {
      kind get clusters 2>/dev/null
      docker compose ls -q 2>/dev/null
    } | grep '^celian-bench-' | grep -v "^$NAME\$" | sort -u | paste -sd, - || true
  )
  tsv load.tsv "$(utc_now)" "$opt" "$phase" "$loadavg" "$mine" "$((total - mine))" "${others:--}"
}

record_ports() {
  local opt=$1 phase=$2 name ports pids
  docker ps --filter "name=$NAME" --format '{{.Names}}\t{{.Ports}}' |
    while IFS=$'\t' read -r name ports; do
      tsv ports.tsv "$opt" "$phase" container "$name" "${ports:--}"
    done
  pids=$(owned_pids | paste -sd, -)
  if [ -n "$pids" ]; then
    { lsof -nP -a -p "$pids" -iTCP -sTCP:LISTEN 2>/dev/null || true; } |
      awk 'NR > 1 { print $1 "\t" $9 }' | sort -u |
      while IFS=$'\t' read -r name ports; do
        tsv ports.tsv "$opt" "$phase" host-process "$name" "$ports"
      done
  fi
}

# Pulled events of the kind node, and Docker pull events of this run's images.
record_pulls() {
  local opt=$1 run=$2 since=$3 status image
  if [ "$opt" = tilt ] || [ "$opt" = kubectl ] || [ "$opt" = aspirek8s ]; then
    { kube get events -A -o json 2>/dev/null || echo '{"items": []}'; } |
      jq -r '.items[] | select(.reason == "Pulled") | .message' |
      sed -n -e 's/^Successfully pulled image "\([^"]*\)".*/pulled|\1/p' \
        -e 's/^Container image "\([^"]*\)" already present.*/present|\1/p' |
      sort -u | while IFS='|' read -r status image; do
        tsv pulls.tsv "$opt" "$run" kind-node "$status" "$image"
      done
  fi
  {
    docker events --since "$since" --until "$(date +%s)" --filter type=image --filter event=pull \
      --format '{{.Actor.ID}}' 2>/dev/null || true
  } | sort -u | while read -r image; do
    case $image in
      *busybox* | *nginx* | *postgres* | *valkey* | *dotnet* | *kindest*)
        tsv pulls.tsv "$opt" "$run" docker pulled "$image"
        ;;
    esac
  done
}

# Networks and volumes left after `task down`: ours by name or label are
# recorded, then removed if unused; the AppHost build output is recorded.
sweep_leftovers() {
  local opt=$1 phase=$2 name
  for name in $(docker network ls --format '{{.Name}}'); do
    case $name in
      "$NAME"*)
        if [ "$(docker network inspect "$name" --format '{{len .Containers}}')" = 0 ] &&
          docker network rm "$name" >>"$LOGS/leftovers.log" 2>&1; then
          tsv leftovers.tsv "$opt" "$phase" network "$name" removed
        else
          tsv leftovers.tsv "$opt" "$phase" network "$name" "left in place"
        fi
        ;;
    esac
  done
  for name in $(docker volume ls -q --filter "label=com.docker.compose.project=$NAME"); do
    if docker volume rm "$name" >>"$LOGS/leftovers.log" 2>&1; then
      tsv leftovers.tsv "$opt" "$phase" volume "$name" removed
    else
      tsv leftovers.tsv "$opt" "$phase" volume "$name" "left in place"
    fi
  done
  # Anything else that appeared since the start, recorded only.
  docker network ls --format '{{.Name}}' | sort >"$TRIAL_DIR/networks-now.txt"
  comm -13 "$TRIAL_DIR/networks-before.txt" "$TRIAL_DIR/networks-now.txt" | while read -r name; do
    tsv leftovers.tsv "$opt" "$phase" network-new "$name" "recorded only"
  done
  docker volume ls -q | sort >"$TRIAL_DIR/volumes-now.txt"
  comm -13 "$TRIAL_DIR/volumes-before.txt" "$TRIAL_DIR/volumes-now.txt" | while read -r name; do
    tsv leftovers.tsv "$opt" "$phase" volume-new "$name" "recorded only"
  done
}

# --- One timed run ------------------------------------------------------------

timed_run() {
  local opt=$1 run=$2 cache api front t0 t_ready t_del0 t_del1 started since stop
  local samples="" i s cont_mem host_mem cpu peak
  cache=$(cache_state "$opt")
  api="api-r$run-$(date +%s)"
  front="marker-r$run-$(date +%s)"
  set_api_marker "$WORK" "$api"
  set_front_marker "$WORK" "$front"
  record_load "$opt" "run-$run"
  refresh_lock
  stop="$TRIAL_DIR/stop-peak-$opt-$run"
  log "$opt run $run ($cache): task up"
  started=$(utc_now)
  since=$(date +%s)
  TOOL_PID=""
  start_peak_sampler "$opt" "$run" "$stop"
  t0=$(now)
  "up_$opt" "$run"
  t_ready=$(wait_markers "$opt" "$api" "$front" "$READY_TIMEOUT") || die "$opt not ready after ${READY_TIMEOUT}s"
  log "$opt run $run: ready in $(seconds_between "$t0" "$t_ready") s"
  sleep 5
  : >"$stop"
  wait "$PEAK_PID" 2>/dev/null || true
  peak=$(awk -F'\t' -v o="$opt" -v r="$run" '$1 == o && $2 == r {
      t = $4 + $6; if (t > m) { m = t; c = $4; h = $6 } }
    END { printf "%.1f\t%.1f\t%.1f", m, c, h }' "$TRIAL_DIR/peak-samples.tsv")
  if [ "$run" = 1 ]; then record_ports "$opt" "run-$run"; fi

  sleep "$(awk -v t="$t_ready" -v w="$IDLE_WAIT" -v n="$(now)" 'BEGIN { d = t + w - n; printf "%.1f", (d > 0 ? d : 0) }')"
  for i in $(seq 1 "$SAMPLES"); do
    s=$(sample "$TRIAL_DIR/idle-detail-$opt-$run-$i.tsv")
    tsv idle-samples.tsv "$opt" "$run" "$i" "$s"
    samples="$samples$s"$'\n'
    if [ "$i" -lt "$SAMPLES" ]; then sleep "$SAMPLE_GAP"; fi
  done
  cont_mem=$(printf '%s' "$samples" | awk -F'\t' 'NF { print $1 }' | median_range | cut -f1)
  host_mem=$(printf '%s' "$samples" | awk -F'\t' 'NF { print $3 }' | median_range | cut -f1)
  cpu=$(printf '%s' "$samples" | awk -F'\t' 'NF { print $2 + $4 }' | median_range | cut -f1)

  if [ "$run" = 1 ] && [ "$LOOP_ITER" -gt 0 ]; then dev_loop "$opt"; fi
  record_pulls "$opt" "$run" "$since"

  log "$opt run $run: task down"
  t_del0=$(now)
  "down_$opt" "$run"
  wait_gone || die "$opt: containers or processes still present after task down"
  t_del1=$(now)
  TOOL_PID=""
  sweep_leftovers "$opt" "run-$run"

  tsv runs.tsv "$opt" "$run" "$cache" "$(seconds_between "$t0" "$t_ready")" \
    "$(seconds_between "$t_del0" "$t_del1")" "$cont_mem" "$host_mem" \
    "$(awk -v a="$cont_mem" -v b="$host_mem" 'BEGIN { printf "%.1f", a + b }')" "$cpu" "$peak" "$started"
}

# --- Development loop ---------------------------------------------------------

dev_loop() {
  local opt=$1 i t0 t1 api front
  api=$(sed -n 's/.*Value = "\(.*\)";/\1/p' "$WORK/api/Marker.cs")
  front=$(grep -o 'marker-[0-9a-z-]*' "$WORK/front/html/index.html" | head -1)
  i=1
  while [ "$i" -le "$LOOP_ITER" ]; do
    front="marker-loop$i-$(date +%s)"
    t0=$(now)
    set_front_marker "$WORK" "$front"
    case $opt in kubectl | aspirek8s) k8s_reload "$opt" front ;; esac
    t1=$(wait_markers "$opt" "$api" "$front" "$LOOP_TIMEOUT") || t1=""
    tsv loop.tsv "$opt" front "$i" "${t1:+$(seconds_between "$t0" "$t1")}"
    log "$opt loop $i: front change seen in ${t1:+$(seconds_between "$t0" "$t1")} s"
    sleep 5
    api="api-loop$i-$(date +%s)"
    t0=$(now)
    set_api_marker "$WORK" "$api"
    case $opt in
      aspire) aspire_api_reload ;;
      kubectl | aspirek8s) k8s_reload "$opt" api ;;
    esac
    t1=$(wait_markers "$opt" "$api" "$front" "$LOOP_TIMEOUT") || t1=""
    tsv loop.tsv "$opt" api "$i" "${t1:+$(seconds_between "$t0" "$t1")}"
    log "$opt loop $i: API change seen in ${t1:+$(seconds_between "$t0" "$t1")} s"
    sleep 5
    i=$((i + 1))
  done
}

# `aspire run` and `aspire start` do not watch the API's source by default.
# The documented step for a C# project resource, with the AppHost left
# running, is `aspire resource <name> rebuild` (aspire.dev, "Hot Reload and
# watch"); `restart` alone keeps the old build. The time of this command is
# part of the measure.
aspire_api_reload() {
  "$ASPIRE_BIN" resource api rebuild --apphost "$WORK/aspire/apphost.cs" --non-interactive --nologo \
    >>"$LOGS/aspire-loop.log" 2>&1 || log "aspire resource api rebuild failed"
}

# --- Kind cluster alone at rest (profiles of US-005) ----------------------------

cluster_idle() {
  local i s t0
  record_load tilt cluster-idle
  t0=$(now)
  kind create cluster --name "$NAME" --image "$KIND_IMAGE" --config "$WORK/kind.yaml" \
    --kubeconfig "$KUBECONFIG" >>"$LOGS/cluster-idle.log" 2>&1 || die "kind create failed"
  kube wait --for=condition=Ready nodes --all --timeout=300s >>"$LOGS/cluster-idle.log" 2>&1
  kube wait --for=condition=Ready pods --all -n kube-system --timeout=300s >>"$LOGS/cluster-idle.log" 2>&1
  log "kind alone: ready in $(seconds_between "$t0" "$(now)") s"
  sleep "$IDLE_WAIT"
  for i in $(seq 1 "$SAMPLES"); do
    s=$(sample)
    tsv cluster-idle.tsv "$i" "$s"
    if [ "$i" -lt "$SAMPLES" ]; then sleep "$SAMPLE_GAP"; fi
  done
  kind delete cluster --name "$NAME" --kubeconfig "$KUBECONFIG" >>"$LOGS/cluster-idle.log" 2>&1
  wait_gone || die "kind cluster still present"
}

# --- Series -------------------------------------------------------------------

series() {
  local opt=$1 run ref first=1
  prepare_work "$opt"
  record_load "$opt" series-start
  if [ "$COLD" = 1 ]; then
    log "$opt: removing the option's images for the cold run"
    remove_built_images
    if [ "$COLD_REMOVE" = 1 ]; then
      for ref in $(option_images "$opt"); do image_remove "$ref"; done
    fi
    timed_run "$opt" 0
    case $opt in aspire | aspirek8s) record_nuget "$opt-run0" ;; esac
    first=0
  fi
  run=1
  while [ "$run" -le "$RUNS" ]; do
    if [ "$first" = 0 ]; then sleep "$PAUSE_BETWEEN_RUNS"; fi
    first=0
    timed_run "$opt" "$run"
    run=$((run + 1))
  done
  case $opt in aspire | aspirek8s) record_nuget "$opt-end" ;; esac
  if [ "$opt" = tilt ] && [ "$CLUSTER_IDLE" = 1 ]; then
    sleep "$PAUSE_BETWEEN_RUNS"
    cluster_idle
  fi
}

# --- Start-up checks ----------------------------------------------------------

check_aspire_version() {
  local v
  v=$(dotnet --version)
  [ "$v" = "$DOTNET_SDK_VERSION" ] || die "dotnet SDK $v found, $DOTNET_SDK_VERSION expected"
  tsv versions.tsv dotnet-sdk "$v"
  v=$("$ASPIRE_BIN" --version 2>/dev/null | tail -1)
  case $v in "$ASPIRE_VERSION"+* | "$ASPIRE_VERSION") ;; *) die "aspire $v found, $ASPIRE_VERSION expected" ;; esac
  tsv versions.tsv aspire "$v"
}

check_versions() {
  local opt v
  for v in docker kubectl jq perl lsof shasum openssl; do
    command -v "$v" >/dev/null || die "$v not found"
  done
  for opt in $OPTIONS; do
    if [ "$opt" = aspirek8s ]; then
      v=$(helm version --short 2>/dev/null)
      case $v in "$HELM_VERSION"+* | "$HELM_VERSION") ;; *) die "helm $v found, $HELM_VERSION expected" ;; esac
      tsv versions.tsv helm "$v"
      check_aspire_version
    fi
    case $opt in
      tilt | kubectl | aspirek8s)
        if [ "$opt" = tilt ]; then
          v=$(tilt version | awk '{ print $1 }' | tr -d ,)
          [ "$v" = "$TILT_VERSION" ] || die "tilt $v found, $TILT_VERSION expected"
          tsv versions.tsv tilt "$v"
        fi
        v=$(kind version | awk '{ print $2 }')
        [ "$v" = "$KIND_VERSION" ] || die "kind $v found, $KIND_VERSION expected"
        tsv versions.tsv kind "$v"
        v=$(kubectl version --client -o json | jq -r '.clientVersion.minor' | tr -dc '0-9')
        case " $KUBECTL_MINORS " in
          *" $v "*) ;;
          *) die "kubectl 1.$v is too far from the kind node (1.36)" ;;
        esac
        tsv versions.tsv kubectl "$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion')"
        ;;
      compose)
        v=$(docker compose version --short)
        [ "$v" = "$COMPOSE_VERSION" ] || die "docker compose $v found, $COMPOSE_VERSION expected"
        tsv versions.tsv compose "$v"
        ;;
      aspire) check_aspire_version ;;
      *) die "unknown option: $opt" ;;
    esac
  done
  tsv versions.tsv docker "$(docker version --format '{{.Server.Version}}')"
  tsv versions.tsv engine "$(docker info --format '{{.OperatingSystem}} {{.NCPU}} CPU {{.MemTotal}} B cgroup v{{.CgroupVersion}}')"
  tsv versions.tsv host "$(sysctl -n hw.model 2>/dev/null || uname -m) $(sw_vers -productVersion 2>/dev/null || uname -r)"
}

# Every image reference of the script appears as is in the stack files.
check_stack_pins() {
  local ref
  for ref in "$SDK_IMAGE" "$ASPNET_IMAGE" "$NGINX_IMAGE" "$BUSYBOX_IMAGE" "$POSTGRES_IMAGE" "$VALKEY_IMAGE"; do
    grep -rqF "${ref#*@sha256:}" "$STACK" || die "digest of $ref not found in $STACK"
  done
}

check_free() {
  local port
  [ -z "$(my_containers)" ] || die "a container named $NAME* already exists"
  if kind get clusters 2>/dev/null | grep -qx "$NAME"; then die "a kind cluster $NAME already exists"; fi
  if docker compose ls -a -q 2>/dev/null | grep -qx "$NAME"; then die "a Compose project $NAME already exists"; fi
  for port in $API_PORT $FRONT_PORT $TILT_PORT $ASPIRE_PORTS; do
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then die "port $port is already in use"; fi
  done
}

record_preexisting() {
  local ref
  for ref in "$KIND_IMAGE" "$SDK_IMAGE" "$ASPNET_IMAGE" "$NGINX_IMAGE" "$BUSYBOX_IMAGE" \
    "$POSTGRES_IMAGE" "$VALKEY_IMAGE" "$AZURELINUX_IMAGE"; do
    if image_present "$ref"; then
      PREEXISTING_IMAGES="$PREEXISTING_IMAGES $ref"
      tsv leftovers.tsv start start image-preexisting "$ref" "never removed"
    fi
  done
  for ref in $(dcptun_images); do
    DCPTUN_PREEXISTING=1
    tsv leftovers.tsv start start image-preexisting "$ref" "never removed"
  done
}

# Passwords generated for this trial, in files readable by the user only.
generate_secrets() {
  local pg valkey
  pg=$(openssl rand -hex 16)
  valkey=$(openssl rand -hex 16)
  printf '%s' "$pg" >"$TRIAL_DIR/pg-password"
  printf '%s' "$valkey" >"$TRIAL_DIR/valkey-password"
  printf 'PG_PASSWORD=%s\n' "$pg" >"$TRIAL_DIR/compose.env"
  printf 'export Parameters__pgpassword=%s\nexport Parameters__valkeypassword=%s\n' "$pg" "$valkey" \
    >"$TRIAL_DIR/aspire.env"
}

# --- Cleanup ------------------------------------------------------------------

cleanup() {
  local rc=$? opt dir
  trap - EXIT INT TERM
  set +e
  if [ -n "$TRIAL_DIR" ]; then
    if [ -n "${PEAK_PID:-}" ]; then kill "$PEAK_PID" 2>/dev/null; fi
    if [ -n "$TOOL_PID" ]; then
      kill -INT "$TOOL_PID" 2>/dev/null
      sleep 2
    fi
    for opt in $OPTIONS; do
      WORK="$TRIAL_DIR/work/$opt"
      [ -d "$WORK" ] || continue
      case $opt in
        tilt | kubectl | aspirek8s)
          if kind get clusters 2>/dev/null | grep -qx "$NAME"; then
            log "cleanup: deleting the kind cluster $NAME"
            kind delete cluster --name "$NAME" --kubeconfig "$KUBECONFIG" >>"$LOGS/cleanup.log" 2>&1
          fi
          ;;
        compose)
          if docker compose ls -a -q 2>/dev/null | grep -qx "$NAME"; then
            log "cleanup: removing the Compose project $NAME"
            down_compose cleanup
          fi
          ;;
        aspire) [ -z "$(my_containers)" ] || down_aspire cleanup ;;
      esac
    done
    wait_gone || log "cleanup: containers or processes of $NAME still present: $(my_containers | paste -sd, -)"
    sweep_leftovers cleanup end
    remove_built_images
    if [ "$KIND_NETWORK_EXISTED" = 0 ] && docker network inspect kind >/dev/null 2>&1 &&
      [ "$(docker network inspect kind --format '{{len .Containers}}')" = 0 ]; then
      log "cleanup: removing the kind network created by this run"
      docker network rm kind >>"$LOGS/cleanup.log" 2>&1
    fi
    for dir in $(new_runfile_dirs); do
      tsv leftovers.tsv cleanup end runfile "$dir" removed
      rm -rf "${RUNFILE_DIR:?}/$dir"
    done
    docker images --digests --format '{{.Repository}}:{{.Tag}}@{{.Digest}}' | sort >"$TRIAL_DIR/images-after.txt"
    release_lock
    log "results in $TRIAL_DIR"
  fi
  exit "$rc"
}

# --- Summary ------------------------------------------------------------------

summarize() {
  local opt column name values
  tsv summary.tsv option metric runs values median range
  for opt in $OPTIONS; do
    for column in 4:up_s 5:down_s 8:mem_total_mib 6:mem_containers_mib 7:mem_host_mib 9:cpu_pct 10:peak_total_mib; do
      name=${column#*:}
      values=$(awk -F'\t' -v o="$opt" -v c="${column%%:*}" \
        '$1 == o && $2 != "run" && $2 != "0" { print $c }' "$TRIAL_DIR/runs.tsv")
      tsv summary.tsv "$opt" "$name" "$(printf '%s\n' "$values" | grep -c .)" \
        "$(printf '%s\n' "$values" | paste -sd, -)" "$(printf '%s\n' "$values" | median_range)"
    done
    for name in front api; do
      values=$(awk -F'\t' -v o="$opt" -v k="$name" '$1 == o && $2 == k && $4 != "" { print $4 }' "$TRIAL_DIR/loop.tsv")
      tsv summary.tsv "$opt" "loop_${name}_s" "$(printf '%s\n' "$values" | grep -c .)" \
        "$(printf '%s\n' "$values" | paste -sd, -)" "$(printf '%s\n' "$values" | median_range)"
    done
  done
}

# --- Main ---------------------------------------------------------------------

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

  export KUBECONFIG="$TRIAL_DIR/kubeconfig"
  export NUGET_PACKAGES="$TRIAL_DIR/nuget"
  export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 ASPIRE_CLI_TELEMETRY_OPTOUT=true
  export TILT_DISABLE_ANALYTICS=true
  # Helm keeps its cache, configuration and data in the trial directory.
  export HELM_CACHE_HOME="$TRIAL_DIR/helm/cache" HELM_CONFIG_HOME="$TRIAL_DIR/helm/config"
  export HELM_DATA_HOME="$TRIAL_DIR/helm/data"
  : >"$KUBECONFIG"

  tsv runs.tsv option run cache up_s down_s mem_containers_mib mem_host_mib mem_total_mib \
    cpu_pct peak_total_mib peak_containers_mib peak_host_mib started_utc
  tsv idle-samples.tsv option run sample cont_mib cont_cpu host_mib host_cpu
  tsv peak-samples.tsv option run utc cont_mib cont_cpu host_mib host_cpu
  tsv cluster-idle.tsv sample cont_mib cont_cpu host_mib host_cpu
  tsv loop.tsv option change iteration seconds
  tsv ports.tsv option phase kind name address
  tsv pulls.tsv option run source status image
  tsv images.tsv image size_bytes compressed_bytes
  tsv load.tsv utc option phase loadavg_1_5_15 own_containers other_containers other_benchmarks
  tsv leftovers.tsv option phase type name action
  tsv versions.tsv item version

  # Start-up checks first, without any trap: a refusal deletes nothing.
  check_versions
  check_stack_pins
  check_free
  acquire_lock
  # Inventory before any path that can clean up: the "kind" network, the
  # images and the build outputs present now are never removed, even if the
  # second check below refuses to go on.
  if docker network inspect kind >/dev/null 2>&1; then KIND_NETWORK_EXISTED=1; fi
  record_preexisting
  docker network ls --format '{{.Name}}' | sort >"$TRIAL_DIR/networks-before.txt"
  docker volume ls -q | sort >"$TRIAL_DIR/volumes-before.txt"
  docker images --digests --format '{{.Repository}}:{{.Tag}}@{{.Digest}}' | sort >"$TRIAL_DIR/images-before.txt"
  runfile_dirs >"$TRIAL_DIR/runfile-before.txt"
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  # Checked again with the lock held: another benchmark may have started.
  check_free
  generate_secrets
  # A tool directory of its own (dotnet tool install --tool-path), never a
  # shared bin directory.
  case $ASPIRE_BIN in
    */bin/*) ;;
    /*) ASPIRE_MATCH="$(dirname "$ASPIRE_BIN")/" ;;
  esac
  log "trial directory: $TRIAL_DIR"

  for opt in $OPTIONS; do
    series "$opt"
    sleep "$PAUSE_BETWEEN_RUNS"
  done
  record_images
  summarize
  column -t -s "$(printf '\t')" "$TRIAL_DIR/summary.tsv" >&2 || true
}

main "$@"
