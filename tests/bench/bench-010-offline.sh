#!/usr/bin/env bash
# BENCH-010: start `task up` on kind without any public registry (R-25,
# condition 7 of ADR-004, condition 4 of ADR-005 and ADR-006).
#
# The stack is the one of BENCH-005 (tests/bench/bench-005/stack) in option
# O4: kind cluster, docker build of the API and the front, kind load, then
# kubectl apply -k. "Ready" is the BENCH-005 probe: the API and the front
# answer with this run's markers, Postgres and Valkey accept a connection.
#
# Options (mechanisms):
#   base     the stack as in BENCH-005, online at every start: the memory
#            base of M7 (node with the mechanism minus this node);
#   keep     O1: `task down` deletes the application namespace and keeps the
#            cluster; the next `task up` reuses it (test T1);
#   mirror   O2: a local registry, pull-through cache of Docker Hub, on the
#            "kind" network; the node's containerd sends docker.io to it and
#            every public registry to a dead end. REGISTRY=distribution or
#            REGISTRY=zot (tests T1 and T2: `task down` deletes the cluster).
#            The script never starts the registry: see MIRROR_PHASE below;
#   archive  O3: OCI archives loaded by `kind load image-archive` into a
#            new cluster (T1 and T2). ARCHIVE_SOURCE picks where they come
#            from. "zot": cut from the OCI layouts that zot keeps on disk
#            (ARCHIVE_SRC, the storage of a `mirror` run with zot), so they
#            keep the registry's index: no OCI copy tool is installed on the
#            measuring machine. "docker-save": `docker save` of the images
#            the host's Docker already holds by digest, the only source that
#            needs neither a registry container nor a copy out of the node;
#            with a classic image store it is expected to lose the index
#            digest (R-25), and the offline runs show whether it does.
#
# An offline run that does not reach "ready" is a result, not an error: as
# soon as a pod of the stack has been in ErrImagePull or ImagePullBackOff
# for PULL_FAIL_GRACE s, the run is recorded "not-ready" with the images in
# cause, and the series goes on. An archive that `kind load image-archive`
# refuses is recorded the same way. An online run that fails stops the
# script.
#
# "Offline" is simulated in the node only, never on the host: the trial's
# registry host directory, mounted read-only on /etc/containerd/certs.d,
# receives one hosts.toml per public registry, plus _default, whose server
# is a dead end (https://127.0.0.1:9, nothing listens there inside the
# node) and whose only other host, for docker.io in option mirror, is the
# local mirror. containerd uses "server" as the fallback once every host has
# been tried (docs/hosts.md), so nothing falls back to the upstream. Proof:
# the node's Pulled events, and witness pulls (tests/bench/bench-010/
# witness.yaml) that must fail and name the dead end. The registry used by
# option mirror loses its own upstream the same way: its offline
# configuration points it to https://127.0.0.1:9.
#
# For each option: run 0 is the first `task up`, with network (M2), then
# `task down`; then RUNS offline runs, each followed by `task down`. Option
# base has RUNS online runs and no run 0. Per run:
#   - `task up` time, from the first command to the first ready probe line;
#   - images pulled by the node (Pulled events) and by Docker (pull events);
#   - requests served by the mirror (its logs), for option mirror;
#   - memory at rest, IDLE_WAIT s after ready: the kind node and the mirror
#     (docker stats), 3 samples 10 s apart;
#   - offline runs only: witness pulls, then their outcome;
#   - the image names the kubelet reports for the node (node status), to
#     see under which name an archive was imported;
#   - options keep and mirror: what stays in memory IDLE_WAIT s after
#     `task down` (M8), 3 samples 10 s apart.
# Once per series: the volume added on disk (M5), the published ports (M9).
#
# Usage: tests/bench/bench-010-offline.sh [TRIAL_DIR]
#   TRIAL_DIR, if given, must be missing or empty (default: mktemp -d).
#   Environment:
#     OPTIONS=base       options, run in this order (base keep mirror archive)
#     RUNS=3             offline runs per option (online runs for base)
#     IDLE_WAIT=120      seconds between "ready" and the first memory sample
#     REGISTRY=distribution  registry of option mirror: distribution or zot
#     REGISTRY_DIR=      directory of the mirror (config/ and storage/),
#                        required by option mirror and kept between phases
#     MIRROR_PHASE=      option mirror runs in four steps, OPTIONS=mirror:
#                        prepare-online  writes the online configuration in
#                                        REGISTRY_DIR and prints the command
#                                        that starts the registry; no lock,
#                                        no cluster;
#                        online          run 0 only, with the registry
#                                        started by that command;
#                        prepare-offline the same with the offline
#                                        configuration, once the registry of
#                                        the online phase is gone;
#                        offline         runs 1 to RUNS.
#     REGISTRY_REMOVE_AT_EXIT=1  the registry of the phase (ours: label,
#                        image and mounts checked) is removed at exit; its
#                        storage stays in REGISTRY_DIR
#     BENCH_LOCK_REUSE=0 1: a lock whose owner file starts with "BENCH-010 "
#                        is reused and left in place at exit, so that the
#                        operator can hold it across the phases of mirror
#     ARCHIVE_SOURCE=docker-save  source of the archives: docker-save or zot
#     ARCHIVE_SRC=       storage directory of a zot mirror, for ARCHIVE_SOURCE=zot
#     BENCH_LOCK=        a directory used as a lock shared with the other
#                        benchmarks: created before the first measure, owner
#                        file "BENCH-010 <utc>", refreshed at each run,
#                        removed at exit. A lock held by anyone else is
#                        never removed: the script exits with code 75.
#   Results (TSV) in TRIAL_DIR: versions, runs, samples, pulls, docker-pulls,
#   node-images, mirror, witness, failures, held, volume, ports, load,
#   leftovers, summary; command output in TRIAL_DIR/logs/.
# Needs: bash >= 3.2, docker, kind and kubectl at the versions below, jq,
#   perl, openssl, shasum, du, tar, cmp.
#
# Safety:
#   - the cluster is named celian-bench-010 and the registry
#     celian-bench-010-mirror (celian-bench-010-registry, the name of an
#     earlier draft, belongs to a stopped container this script must not
#     touch), with the registry's name as suffix:
#     celian-bench-010-mirror-distribution or celian-bench-010-mirror-zot.
#     The script refuses to start if the cluster exists, if the
#     lock is held, or if a registry container of that name exists without
#     the label org.celian.bench=010, with another image or other mounts.
#     Its EXIT trap is set only after these checks and after the inventory,
#     so a refusal deletes nothing;
#   - the script runs no `docker run`, `docker start` nor `docker restart`.
#     A command run inside a script is invisible to the permission rules of
#     a Claude Code session: the registry is started by the command that
#     MIRROR_PHASE=prepare-* prints, run on its own, so that the user sees
#     it and consents. It publishes no port on the host; the script connects
#     it to the "kind" network, where the node reaches it. Going offline
#     means a new container with the offline configuration, not a restart.
#     The script uses a registry only if its label, image and mounts match,
#     and removes it at exit (REGISTRY_REMOVE_AT_EXIT=1);
#   - umask 077; KUBECONFIG and the registry host directory live in
#     TRIAL_DIR; ~/.kube is not used. The Postgres password is drawn by
#     openssl and goes through a pipe to `kubectl create -f -` (R-20): it is
#     neither written to a file nor passed as an argument;
#   - no curl, no `docker exec`, no `docker cp`. Built images are removed at
#     exit; pulled images stay cached; archives stay in TRIAL_DIR/archives.
set -euo pipefail
umask 077

# --- Pinned versions ----------------------------------------------------------

readonly KIND_VERSION="v0.33.0"
readonly KUBECTL_MINORS="35 36 37"
# Node image of ADR-004; the same reference is in bench-010/kind.yaml.
readonly KIND_IMAGE="kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed"
# Stack images, pinned by digest in the BENCH-005 stack (read on 2026-11-19).
readonly SDK_IMAGE="mcr.microsoft.com/dotnet/sdk:10.0.404@sha256:bef136a371963aaa46ec97882845ef6f54dec15728bb4b128b1c2a400ffbc9b4"
readonly ASPNET_IMAGE="mcr.microsoft.com/dotnet/aspnet:10.0.15@sha256:12b1135f5f8b3c0a214f2a680ff2033dff4f684f445d6c697d9524ceeb303586"
readonly NGINX_IMAGE="nginx:1.30.7-alpine@sha256:bef154735288bc38d99fac41ae63730684bcc661503673a04a0f9bc526ba8598"
readonly BUSYBOX_IMAGE="busybox:1.37.0@sha256:a7dbc319b1438115a207e11930dc4bb3e643dcb3ec0bdd694bb36cd8fad289ec"
readonly POSTGRES_IMAGE="postgres:18.7-alpine@sha256:ff64c9e3bdf8e2120107d3559de8db314e8305f7e38c5105903c6295876738ff"
readonly VALKEY_IMAGE="valkey/valkey:9.1.4-alpine@sha256:56729e68bdda139cbd3f6a2538683dc3523325fc5711ea1a379938f1b37893f0"
# Registries of option mirror, pinned by index digest (read on 2026-11-20).
readonly DISTRIBUTION_IMAGE="registry:3.1.2@sha256:82f6ff4a7f982960c8aa51617fea3aabc485df6e55cce80d22deb1de36f1bc3c"
readonly ZOT_IMAGE="ghcr.io/project-zot/zot:v2.1.23@sha256:9d3de83ac2099e6f4843045b4c9b65b7e8baf40f92d28f54906dee9d4d390fd7"

readonly NAME="celian-bench-010"
readonly REG_LABEL="org.celian.bench=010"
readonly KUBE_CONTEXT="kind-$NAME"
readonly NODE="$NAME-control-plane"
readonly NS=app
readonly DEAD_END="https://127.0.0.1:9"
# Registry namespaces sent to the dead end; _default covers the others.
readonly PUBLIC_REGISTRIES="_default docker.io quay.io registry.k8s.io ghcr.io mcr.microsoft.com gcr.io public.ecr.aws"
# Images the node pulls for the stack (the API and the front are built and
# loaded by kind load, the base images of their builds stay on the host).
readonly NODE_IMAGES="$POSTGRES_IMAGE $VALKEY_IMAGE $BUSYBOX_IMAGE"
readonly SAMPLES=3
readonly SAMPLE_GAP=10
readonly PAUSE_BETWEEN_RUNS=15
readonly READY_TIMEOUT=900
readonly WITNESS_WAIT=60
# Seconds a stack pod may stay in ErrImagePull or ImagePullBackOff before an
# offline run is recorded "not-ready".
readonly PULL_FAIL_GRACE=45
readonly LOCK_OLD_MIN=90

OPTIONS="${OPTIONS:-base}"
RUNS="${RUNS:-3}"
IDLE_WAIT="${IDLE_WAIT:-120}"
REGISTRY="${REGISTRY:-distribution}"
REGISTRY_DIR="${REGISTRY_DIR:-}"
ARCHIVE_SOURCE="${ARCHIVE_SOURCE:-docker-save}"
ARCHIVE_SRC="${ARCHIVE_SRC:-}"
MIRROR_PHASE="${MIRROR_PHASE:-}"
REGISTRY_REMOVE_AT_EXIT="${REGISTRY_REMOVE_AT_EXIT:-1}"
BENCH_LOCK="${BENCH_LOCK:-}"
BENCH_LOCK_REUSE="${BENCH_LOCK_REUSE:-0}"
readonly OPTIONS RUNS IDLE_WAIT REGISTRY ARCHIVE_SOURCE ARCHIVE_SRC MIRROR_PHASE REGISTRY_REMOVE_AT_EXIT BENCH_LOCK BENCH_LOCK_REUSE

# One container name per registry, never celian-bench-010-registry (an
# earlier draft's stopped container, not ours).
readonly REG_NAME="$NAME-mirror-$REGISTRY"
readonly MIRROR_URL="http://$REG_NAME:5000"

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
readonly STACK="$SCRIPT_DIR/bench-005/stack"
readonly FILES="$SCRIPT_DIR/bench-010"

TRIAL_DIR=""
LOGS=""
WORK=""
CERTS=""
LOCK_HELD=0
LOCK_REUSED=0
LOCK_TAKEN=""
REG_OURS=0
REG_IMAGE=""
ARCHIVE_VARIANT=""
API_TAG=""
FRONT_TAG=""

# --- Helpers ------------------------------------------------------------------

log() { printf '[bench-010 %s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
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

median() {
  sort -n | awk '{ v[NR] = $1 } END {
    if (NR == 0) { print "-"; exit }
    m = (NR % 2) ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2
    printf "%.1f\n", m }'
}

# kubectl on this script's cluster only, whatever the current context.
kube() { kubectl --context "$KUBE_CONTEXT" --request-timeout=10s "$@"; }

cluster_exists() { kind get clusters 2>/dev/null | grep -qx "$NAME"; }
registry_exists() { docker container inspect "$REG_NAME" >/dev/null 2>&1; }

# --- Lock shared with the other benchmarks -----------------------------------

lock_age_min() {
  local mtime
  mtime=$(stat -c %Y "$BENCH_LOCK" 2>/dev/null || stat -f %m "$BENCH_LOCK" 2>/dev/null || echo 0)
  echo $((($(date +%s) - mtime) / 60))
}

# A lock this script did not take is never removed, however old: an old
# lock is only reported as such, and a human decides.
acquire_lock() {
  local age owner
  [ -n "$BENCH_LOCK" ] || return 0
  if ! mkdir "$BENCH_LOCK" 2>/dev/null; then
    owner=$(cat "$BENCH_LOCK/owner" 2>/dev/null || echo unknown)
    age=$(lock_age_min)
    if [ "$BENCH_LOCK_REUSE" = 1 ] && [ "${owner#BENCH-010 }" != "$owner" ]; then
      LOCK_REUSED=1
      log "lock $BENCH_LOCK held by this benchmark ('$owner'): reused, left in place at exit"
      return 0
    fi
    if [ "$age" -ge "$LOCK_OLD_MIN" ]; then
      log "lock held by '$owner' for ${age} min, older than ${LOCK_OLD_MIN} min: left in place, check it by hand"
    else
      log "lock held by '$owner' for ${age} min: refusing to start"
    fi
    exit 75
  fi
  LOCK_TAKEN=$(utc_now)
  printf 'BENCH-010 %s\n' "$LOCK_TAKEN" >"$BENCH_LOCK/owner"
  LOCK_HELD=1
  log "lock $BENCH_LOCK taken"
}

# The owner file is replaced and the directory touched, so that both show a
# fresh date: a series of several options can last longer than 90 minutes.
refresh_lock() {
  [ "$LOCK_HELD" = 1 ] || [ "$LOCK_REUSED" = 1 ] || return 0
  grep -q '^BENCH-010 ' "$BENCH_LOCK/owner" 2>/dev/null || return 0
  printf 'BENCH-010 %s (series started %s)\n' "$(utc_now)" "${LOCK_TAKEN:-before this phase}" >"$BENCH_LOCK/owner.new"
  mv "$BENCH_LOCK/owner.new" "$BENCH_LOCK/owner"
  touch "$BENCH_LOCK"
}

release_lock() {
  if [ "$LOCK_HELD" = 1 ] && grep -q '^BENCH-010 ' "$BENCH_LOCK/owner" 2>/dev/null; then
    rm -rf "$BENCH_LOCK"
    log "lock $BENCH_LOCK released"
  fi
  LOCK_HELD=0
}

# --- Registry host directory of the node (the "network switch") --------------

write_hosts() {
  local ns=$1 mirror=${2:-}
  mkdir -p "$CERTS/$ns"
  {
    printf '# BENCH-010: dead end, no fallback to the upstream registry.\n'
    printf 'server = "%s"\n' "$DEAD_END"
    if [ -n "$mirror" ]; then
      printf '\n[host."%s"]\n  capabilities = ["pull", "resolve"]\n' "$mirror"
    fi
  } >"$CERTS/$ns/hosts.toml.new"
  chmod 644 "$CERTS/$ns/hosts.toml.new"
  mv "$CERTS/$ns/hosts.toml.new" "$CERTS/$ns/hosts.toml"
}

# online: empty directory, containerd's defaults (the upstream registries).
# offline: every public registry to the dead end.
# mirror: the same, except docker.io, sent to the local mirror first.
set_network() {
  local mode=$1 ns
  find "$CERTS" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  case $mode in
    online) ;;
    offline | mirror)
      for ns in $PUBLIC_REGISTRIES; do write_hosts "$ns"; done
      if [ "$mode" = mirror ]; then write_hosts docker.io "$MIRROR_URL"; fi
      ;;
  esac
  tsv network.tsv "$(utc_now)" "$mode" "$(find "$CERTS" -name hosts.toml | wc -l | tr -d ' ')"
  log "node registry hosts: $mode"
}

# --- The local mirror (option mirror) -----------------------------------------

registry_image() {
  case $REGISTRY in
    distribution) echo "$DISTRIBUTION_IMAGE" ;;
    zot) echo "$ZOT_IMAGE" ;;
    *) die "unknown REGISTRY: $REGISTRY" ;;
  esac
}

registry_config_file() {
  case $REGISTRY in
    distribution) echo "config.yml" ;;
    zot) echo "config.json" ;;
  esac
}

# The command that starts the mirror, printed by MIRROR_PHASE=prepare-*:
# bridge network, no published port, image pinned by digest, configuration
# read-only. The script never runs it (see Safety above).
registry_run_command() {
  local file cmd
  file=$(registry_config_file)
  case $REGISTRY in
    distribution) cmd="/etc/bench-010/$file" ;;
    zot) cmd="serve /etc/bench-010/$file" ;;
  esac
  printf 'docker run -d --name %s --label %s --network bridge -v %s/config:/etc/bench-010:ro -v %s/storage:/var/lib/registry %s %s\n' \
    "$REG_NAME" "$REG_LABEL" "$REGISTRY_DIR" "$REGISTRY_DIR" "$REG_IMAGE" "$cmd"
}

# MIRROR_PHASE=prepare-online or prepare-offline: writes the configuration
# of that mode in REGISTRY_DIR/config, then prints the command above. It
# refuses while a container of that name exists: that one would keep the
# configuration it read when it started.
prepare_registry() {
  local mode=$1 file
  file=$(registry_config_file)
  if registry_exists; then
    die "$REG_NAME exists: the cleanup of the previous phase removes it, prepare the $mode phase after"
  fi
  mkdir -p "$REGISTRY_DIR/config" "$REGISTRY_DIR/storage"
  chmod 755 "$REGISTRY_DIR" "$REGISTRY_DIR/config"
  cat "$FILES/$REGISTRY/config-$mode.${file##*.}" >"$REGISTRY_DIR/config/$file"
  chmod 644 "$REGISTRY_DIR/config/$file"
  log "$REGISTRY: $mode configuration written in $REGISTRY_DIR/config; start the registry with:"
  registry_run_command
}

# MIRROR_PHASE=online or offline: the registry runs, is ours (check_registry)
# and its configuration directory holds the configuration of the phase.
require_registry() {
  local mode=$1 file
  file=$(registry_config_file)
  [ "$REG_OURS" = 1 ] || die "$REG_NAME not found: run MIRROR_PHASE=prepare-$mode, then the command it prints"
  [ "$(docker container inspect -f '{{.State.Running}}' "$REG_NAME")" = true ] || die "$REG_NAME is not running"
  cmp -s "$FILES/$REGISTRY/config-$mode.${file##*.}" "$REGISTRY_DIR/config/$file" ||
    die "$REGISTRY_DIR/config/$file is not the $mode configuration"
  tsv network.tsv "$(utc_now)" "registry-$mode" "$REGISTRY"
  tsv leftovers.tsv start registry "$REG_NAME" "started outside the script, $mode configuration"
  log "registry $REG_NAME: $mode configuration, started outside the script"
}

# The registry container of this benchmark, used only if it is ours.
check_registry() {
  local label image mounts
  registry_exists || return 0
  label=$(docker container inspect -f '{{index .Config.Labels "org.celian.bench"}}' "$REG_NAME")
  [ "$label" = 010 ] || die "$REG_NAME exists without the label $REG_LABEL: not ours"
  image=$(docker container inspect -f '{{.Config.Image}}' "$REG_NAME")
  [ "$image" = "$REG_IMAGE" ] || die "$REG_NAME runs $image, $REG_IMAGE expected"
  mounts=$(docker container inspect -f '{{range .Mounts}}{{.Source}} {{end}}' "$REG_NAME")
  case " $mounts " in
    *" $REGISTRY_DIR/config "*) ;;
    *) die "$REG_NAME does not mount $REGISTRY_DIR/config (found: $mounts)" ;;
  esac
  case " $mounts " in
    *" $REGISTRY_DIR/storage "*) ;;
    *) die "$REG_NAME does not mount $REGISTRY_DIR/storage (found: $mounts)" ;;
  esac
  REG_OURS=1
}

connect_registry() {
  if [ "$(docker container inspect -f '{{json .NetworkSettings.Networks.kind}}' "$REG_NAME")" = null ]; then
    docker network connect kind "$REG_NAME" >>"$LOGS/registry.log" 2>&1 || die "could not connect $REG_NAME to kind"
  fi
}

# Requests the mirror answered since a date: manifests and blobs, by status.
record_mirror() {
  local opt=$1 run=$2 since=$3 out
  out="$LOGS/mirror-$opt-$run.log"
  docker logs --since "$since" "$REG_NAME" >"$out" 2>&1 || true
  # Distribution writes access log lines ("GET /v2/... HTTP/1.1" 200), zot
  # JSON lines ("method":"GET","path":"/v2/...","statusCode":200).
  perl -ne '
    next unless /\b(GET|HEAD)\b/;
    my $m = $1;
    next unless m{/v2/([^ "?]+)/(manifests|blobs)/};
    my ($repo, $kind) = ($1, $2);
    my $s = /"(?:statusCode|status)":\s*(\d{3})/ ? $1 : (/HTTP\/[\d.]+" (\d{3})/ ? $1 : "-");
    $c{"$m\t$repo\t$kind\t$s"}++;
    END { print "$_\t$c{$_}\n" for sort keys %c }' "$out" | while IFS= read -r line; do
    printf '%s\t%s\t%s\n' "$opt" "$run" "$line" >>"$TRIAL_DIR/mirror.tsv"
  done
  tsv mirror.tsv "$opt" "$run" upstream-errors "-" "-" "-" "$(grep -c -E '127\.0\.0\.1:9|connection refused' "$out" || true)"
}

# --- OCI archives (option archive) --------------------------------------------

# repo of "name:tag@digest" in the storage of zot: docker.io/library/x is
# library/x, docker.io/y/x is y/x.
image_repo() {
  local ref=${1%@*}
  ref=${ref%:*}
  case $ref in */*) echo "$ref" ;; *) echo "library/$ref" ;; esac
}

image_digest() { echo "${1#*@}"; }
image_tag() {
  local ref=${1%@*}
  echo "${ref##*:}"
}

blob_size() {
  stat -f %z "$1" 2>/dev/null || stat -c %s "$1"
}

# Blobs of one image manifest: the manifest, its config and its layers.
manifest_blobs() {
  local layout=$1 dgst=$2
  echo "$dgst"
  jq -r '.config.digest, .layers[]?.digest' "$layout/blobs/sha256/${dgst#sha256:}"
}

# Writes TRIAL_DIR/archives/<name>-<variant>.tar: the index of the registry,
# unchanged, with the children of the node's platform only (sparse) or with
# every child present in the layout (full).
build_archive() {
  local ref=$1 variant=$2 arch=$3 repo dgst tag layout out dir list child
  repo=$(image_repo "$ref")
  dgst=$(image_digest "$ref")
  tag=$(image_tag "$ref")
  layout="$ARCHIVE_SRC/$repo"
  [ -f "$layout/blobs/sha256/${dgst#sha256:}" ] || die "index $dgst of $repo not found in $layout"
  dir="$TRIAL_DIR/archives/$(echo "$repo" | tr / _)-$variant"
  out="$dir.tar"
  mkdir -p "$dir"
  list="$dir.blobs"
  echo "$dgst" >"$list"
  case $variant in
    sparse)
      child=$(jq -r --arg a "$arch" '.manifests[] | select(.platform.os == "linux" and .platform.architecture == $a) | .digest' \
        "$layout/blobs/sha256/${dgst#sha256:}" | head -1)
      [ -n "$child" ] || die "no linux/$arch child in $repo@$dgst"
      manifest_blobs "$layout" "$child" >>"$list"
      ;;
    full)
      for child in $(jq -r '.manifests[].digest' "$layout/blobs/sha256/${dgst#sha256:}"); do
        if [ -f "$layout/blobs/sha256/${child#sha256:}" ]; then
          manifest_blobs "$layout" "$child" >>"$list"
        else
          tsv volume.tsv archive "$variant" "missing-child" "$repo@$child"
        fi
      done
      ;;
  esac
  printf '{"imageLayoutVersion":"1.0.0"}\n' >"$dir/oci-layout"
  jq -n --arg d "$dgst" --argjson s "$(blob_size "$layout/blobs/sha256/${dgst#sha256:}")" \
    --arg mt "$(jq -r '.mediaType // "application/vnd.oci.image.index.v1+json"' "$layout/blobs/sha256/${dgst#sha256:}")" \
    --arg name "docker.io/${repo}:$tag" --arg tag "$tag" '{
      schemaVersion: 2, mediaType: "application/vnd.oci.image.index.v1+json",
      manifests: [{mediaType: $mt, digest: $d, size: $s,
        annotations: {"io.containerd.image.name": $name, "org.opencontainers.image.ref.name": $tag}}]}' \
    >"$dir/index.json"
  # Blobs staged by hard link (same file system as the mirror's storage),
  # then archived; the staging directory goes away, only the tar stays.
  mkdir -p "$dir/blobs/sha256"
  sort -u "$list" | while read -r child; do
    ln "$layout/blobs/sha256/${child#sha256:}" "$dir/blobs/sha256/${child#sha256:}" 2>/dev/null ||
      cp "$layout/blobs/sha256/${child#sha256:}" "$dir/blobs/sha256/${child#sha256:}"
  done
  tar -cf "$out" -C "$dir" oci-layout index.json blobs
  tsv volume.tsv archive "$variant" "$repo" "$(blob_size "$out")" "$(sort -u "$list" | grep -c .)"
  rm -rf "$dir" "$list"
  echo "$out"
}

build_archives() {
  local variant=$1 arch ref
  arch=$(kube get node "$NODE" -o jsonpath='{.status.nodeInfo.architecture}' 2>/dev/null ||
    docker version --format '{{.Server.Arch}}')
  for ref in $NODE_IMAGES; do build_archive "$ref" "$variant" "$arch" >/dev/null; done
}

# ARCHIVE_SOURCE=docker-save: one archive per image, saved by its digest
# reference from the host's Docker, pulled first only if absent (the pull is
# then logged in volume.tsv, as M6). The index.json of each archive is kept
# in the logs, to compare its digests with the reference's. The time taken
# goes to volume.tsv: a real `task up` would pay it.
build_docker_save_archives() {
  local ref repo out t0 log_file="$LOGS/archive-docker-save.log"
  t0=$(now)
  for ref in $NODE_IMAGES; do
    repo=$(image_repo "$ref" | tr / _)
    out="$TRIAL_DIR/archives/$repo-docker-save.tar"
    if ! docker image inspect "$ref" >/dev/null 2>&1; then
      docker pull "$ref" >>"$log_file" 2>&1 || die "docker pull $ref failed, see $log_file"
      tsv volume.tsv archive docker-save host-pull "$ref"
    fi
    docker save -o "$out" "$ref" >>"$log_file" 2>&1 || die "docker save $ref failed, see $log_file"
    tar -xOf "$out" index.json >"$LOGS/archive-docker-save-$repo-index.json" 2>/dev/null || true
    tsv volume.tsv archive docker-save "$repo" "$(blob_size "$out")" \
      "$(jq -r '[.manifests[].digest] | join(",")' "$LOGS/archive-docker-save-$repo-index.json" 2>/dev/null || echo -)"
  done
  tsv volume.tsv archive docker-save build-seconds "$(seconds_between "$t0" "$(now)")"
  ARCHIVE_VARIANT=docker-save
  log "archive: offline runs use the docker-save archives"
}

# Loads every archive of the variant; returns non-zero on the first failure.
load_archives() {
  local variant=$1 log_file=$2 ref repo
  for ref in $NODE_IMAGES; do
    repo=$(image_repo "$ref" | tr / _)
    if ! kind load image-archive "$TRIAL_DIR/archives/$repo-$variant.tar" --name "$NAME" >>"$log_file" 2>&1; then
      log "kind load image-archive failed for $repo ($variant), see $log_file"
      return 1
    fi
  done
}

# --- Stack copy, markers, up and down ----------------------------------------

prepare_work() {
  WORK="$TRIAL_DIR/work"
  if [ ! -d "$WORK" ]; then
    mkdir -p "$WORK"
    cp -R "$STACK/." "$WORK/"
    chmod -R go+rX "$WORK/front" "$WORK/probe.sh"
  fi
  sed "s|@CERTS_DIR@|$CERTS|" "$FILES/kind.yaml" >"$TRIAL_DIR/kind.yaml"
}

set_markers() {
  printf 'namespace Api;\n\ninternal static class Marker\n{\n    public const string Value = "%s";\n}\n' \
    "$1" >"$WORK/api/Marker.cs"
  printf '<!doctype html>\n<html lang="fr">\n<head><meta charset="utf-8"><title>BENCH-010</title></head>\n<body><p>%s</p></body>\n</html>\n' \
    "$2" >"$WORK/front/html/index.html.tmp"
  chmod 644 "$WORK/front/html/index.html.tmp"
  mv "$WORK/front/html/index.html.tmp" "$WORK/front/html/index.html"
}

create_cluster() {
  kind create cluster --name "$NAME" --config "$TRIAL_DIR/kind.yaml" --kubeconfig "$KUBECONFIG" \
    >>"$1" 2>&1 || die "kind create failed, see $1"
}

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

# The Secret goes through a pipe to `kubectl create -f -` (R-20, ADR-006
# condition 1): printf is a shell builtin, the value never appears in a
# process argument list nor in a file.
create_secrets() {
  local log_file=$1
  kube create namespace "$NS" >>"$log_file" 2>&1
  printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: pg-auth\n  namespace: %s\ntype: Opaque\nstringData:\n  password: "%s"\n' \
    "$NS" "$(openssl rand -hex 16)" | kube create -f - >>"$log_file" 2>&1 || die "Secret pg-auth not created"
  kube -n "$NS" create configmap probe-script --from-file=probe.sh="$WORK/probe.sh" >>"$log_file" 2>&1
}

apply_stack() {
  local log_file=$1 f
  {
    printf 'apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nnamespace: %s\nresources:\n' "$NS"
    for f in "$WORK"/k8s/app/*.yaml "$WORK"/k8s/local/*.yaml "$WORK"/k8s/bench/*.yaml; do
      printf '  - %s\n' "${f#"$WORK"/k8s/}"
    done
    printf 'images:\n  - name: celian-bench-005/api\n    newName: %s/api\n    newTag: "%s"\n' "$NAME" "$API_TAG"
    printf '  - name: celian-bench-005/front\n    newName: %s/front\n    newTag: "%s"\n' "$NAME" "$FRONT_TAG"
  } >"$WORK/k8s/kustomization.yaml"
  kube apply -k "$WORK/k8s" >>"$log_file" 2>&1 || die "kubectl apply failed, see $log_file"
}

# `task up`: cluster (unless kept), archives, Secret, images, manifests.
task_up() {
  local opt=$1 run=$2 log_file="$LOGS/$1-$2.log"
  if ! cluster_exists; then
    create_cluster "$log_file"
    if [ "$opt" = mirror ]; then connect_registry; fi
    # A refused archive is a result of test T1 or T2: the stack goes on, and
    # its pods show whether the images are missing.
    if [ "$opt" = archive ] && [ "$run" != 0 ]; then
      if load_archives "$ARCHIVE_VARIANT" "$log_file"; then
        tsv volume.tsv archive "run-$run" kind-load ok
      else
        tsv volume.tsv archive "run-$run" kind-load failed
      fi
    fi
  fi
  create_secrets "$log_file"
  build_load api "$log_file"
  build_load front "$log_file"
  apply_stack "$log_file"
}

# `task down`: option keep deletes the application, the others the cluster.
task_down() {
  local opt=$1 run=$2 log_file="$LOGS/$1-$2.log"
  case $opt in
    keep) kube delete namespace "$NS" --wait=true --timeout=180s >>"$log_file" 2>&1 || die "namespace $NS not deleted" ;;
    *) kind delete cluster --name "$NAME" --kubeconfig "$KUBECONFIG" >>"$log_file" 2>&1 ;;
  esac
}

# --- The probe ----------------------------------------------------------------

line_matches() {
  local line=$1 api=$2 front=$3
  case $line in *"api=[ok $api]"*) ;; *) return 1 ;; esac
  case $line in *"front=[$front]"*) ;; *) return 1 ;; esac
  case $line in *"pg=[ok]"*) ;; *) return 1 ;; esac
  case $line in *"cache=[]"*) return 1 ;; *"cache=["*) return 0 ;; *) return 1 ;; esac
}

# Images of the stack pods stuck in ErrImagePull or ImagePullBackOff.
pull_errors() {
  { kube -n "$NS" get pods -o json 2>/dev/null || echo '{"items": []}'; } |
    jq -r '[.items[].status | (.initContainerStatuses // []) + (.containerStatuses // []) | .[]
      | select((.state.waiting.reason // "") | test("ErrImagePull|ImagePullBackOff")) | .image]
      | unique | join(",")'
}

# Prints the time of the first matching probe line and returns 0; returns 1
# on timeout, 2 when a pull error has lasted PULL_FAIL_GRACE s. It runs in a
# command substitution: the images in cause go to TRIAL_DIR/pull-failed.tmp.
wait_ready() {
  local api=$1 front=$2 deadline line="" t errors first_error=0 polls=0
  deadline=$(($(date +%s) + READY_TIMEOUT))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    t=$(now)
    line=$(kube -n "$NS" logs deploy/probe --tail=1 2>/dev/null || true)
    if line_matches "$line" "$api" "$front"; then
      echo "$t"
      return 0
    fi
    polls=$((polls + 1))
    if [ $((polls % 10)) = 0 ]; then
      errors=$(pull_errors)
      if [ -z "$errors" ]; then
        first_error=0
      elif [ "$first_error" = 0 ]; then
        first_error=$(date +%s)
      elif [ $(($(date +%s) - first_error)) -ge "$PULL_FAIL_GRACE" ]; then
        printf '%s\n' "$errors" >"$TRIAL_DIR/pull-failed.tmp"
        log "pull errors for ${PULL_FAIL_GRACE} s: $errors"
        return 2
      fi
    fi
    sleep 0.5
  done
  log "last probe line: ${line:-none}"
  return 1
}

# Failed pull events of the stack pods, after a run that did not get ready.
record_failures() {
  local opt=$1 run=$2
  kube -n "$NS" get events -o json >"$LOGS/failed-events-$opt-$run.json" 2>/dev/null || true
  jq -r '[.items[] | select(.reason == "Failed" and (.message | startswith("Failed to pull")))
      | {pod: .involvedObject.name, msg: .message}] | unique_by(.pod) | .[] | [.pod, .msg] | @tsv' \
    "$LOGS/failed-events-$opt-$run.json" 2>/dev/null | while IFS=$'\t' read -r pod msg; do
    tsv failures.tsv "$opt" "$run" "$pod" "$(printf '%s' "$msg" | tr '\t\n' '  ' | cut -c1-400)"
  done
}

# Image names the kubelet reports in the node status (all of them in the
# logs; those of the stack and those named by `ctr import` in the TSV).
record_node_images() {
  local opt=$1 run=$2 out="$LOGS/node-images-$1-$2.txt"
  { kube get node "$NODE" -o json 2>/dev/null || echo '{"status": {"images": []}}'; } |
    jq -r '.status.images[]? | (.names // []) | join(" ")' >"$out"
  grep -E 'postgres|valkey|busybox|import-' "$out" | while IFS= read -r names; do
    tsv node-images.tsv "$opt" "$run" "$names"
  done || true
}

# --- Records ------------------------------------------------------------------

to_mib_awk='function to_mib(v,  n, u) {
  n = v; sub(/[A-Za-z]+$/, "", n); u = v; sub(/^[0-9.]+/, "", u)
  if (u == "B") return n / 1048576
  if (u == "KiB" || u == "kB") return n / 1024
  if (u == "MiB" || u == "MB") return n
  if (u == "GiB" || u == "GB") return n * 1024
  return -1 }'

# Memory of one container, in MiB, or "-" if it does not run.
container_mib() {
  docker stats --no-stream --format '{{.MemUsage}}' "$1" 2>/dev/null |
    awk "$to_mib_awk"'{ split($0, m, " "); printf "%.1f\n", to_mib(m[1]) }' | grep . || echo "-"
}

# SAMPLES samples of the node and of the registry; prints the two medians.
sample_memory() {
  local opt=$1 run=$2 phase=$3 i node reg nodes="" regs=""
  for i in $(seq 1 "$SAMPLES"); do
    node=$(container_mib "$NODE")
    reg="-"
    if [ "$opt" = mirror ]; then reg=$(container_mib "$REG_NAME"); fi
    tsv samples.tsv "$opt" "$run" "$phase" "$i" "$(utc_now)" "$node" "$reg"
    nodes="$nodes$node"$'\n'
    regs="$regs$reg"$'\n'
    if [ "$i" -lt "$SAMPLES" ]; then sleep "$SAMPLE_GAP"; fi
  done
  printf '%s\t%s\n' "$(printf '%s' "$nodes" | grep -v '^-$' | median)" "$(printf '%s' "$regs" | grep -v '^-$' | median)"
}

# Pulled events of this run (fresh namespace or fresh cluster), and Docker
# pull events on the host. Prints "pulled<TAB>present<TAB>failed<TAB>docker",
# "failed" counting the images with at least one "Failed to pull" event.
record_pulls() {
  local opt=$1 run=$2 since=$3 since_epoch=$4 status image pulled present failed docker_pulls
  { kube get events -A -o json 2>/dev/null || echo '{"items": []}'; } |
    jq -r --arg s "$since" '.items[] | select(.reason == "Pulled" or (.reason == "Failed" and (.message | startswith("Failed to pull"))))
      | select((.lastTimestamp // .eventTime // .metadata.creationTimestamp) >= $s) | .message' |
    sed -n -e 's/^Successfully pulled image "\([^"]*\)".*/pulled|\1/p' \
      -e 's/^Container image "\([^"]*\)" already present.*/present|\1/p' \
      -e 's/^Failed to pull image "\([^"]*\)".*/failed|\1/p' |
    sort | uniq -c | while read -r count line; do
    status=${line%%|*}
    image=${line#*|}
    tsv pulls.tsv "$opt" "$run" "$status" "$image" "$count"
  done
  pulled=$(awk -F'\t' -v o="$opt" -v r="$run" '$1 == o && $2 == r && $3 == "pulled" { n += $5 } END { print n + 0 }' "$TRIAL_DIR/pulls.tsv")
  present=$(awk -F'\t' -v o="$opt" -v r="$run" '$1 == o && $2 == r && $3 == "present" { n += $5 } END { print n + 0 }' "$TRIAL_DIR/pulls.tsv")
  failed=$(awk -F'\t' -v o="$opt" -v r="$run" '$1 == o && $2 == r && $3 == "failed" { n++ } END { print n + 0 }' "$TRIAL_DIR/pulls.tsv")
  docker events --since "$since_epoch" --until "$(date +%s)" --filter type=image --filter event=pull \
    --format '{{.Actor.ID}}' 2>/dev/null | sort -u >"$TRIAL_DIR/docker-pulls-$opt-$run.txt" || true
  while read -r image; do
    [ -n "$image" ] && tsv docker-pulls.tsv "$opt" "$run" "$image"
  done <"$TRIAL_DIR/docker-pulls-$opt-$run.txt"
  docker_pulls=$(grep -c . "$TRIAL_DIR/docker-pulls-$opt-$run.txt" || true)
  printf '%s\t%s\t%s\t%s\n' "$pulled" "$present" "$failed" "$docker_pulls"
}

# Witness pulls: each pod's outcome after at most WITNESS_WAIT seconds, with
# the last pull error the kubelet reported for it.
run_witnesses() {
  local opt=$1 run=$2 deadline pod phase waiting msg
  kube create namespace witness >>"$LOGS/witness.log" 2>&1
  kube -n witness apply -f "$FILES/witness.yaml" >>"$LOGS/witness.log" 2>&1
  deadline=$(($(date +%s) + WITNESS_WAIT))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    waiting=$(kube -n witness get pods -o json | jq -r '[.items[] | select(
      (.status.containerStatuses // [] | map(.state.waiting.reason // "") | any(test("ErrImagePull|ImagePullBackOff|InvalidImageName"))) or
      (.status.containerStatuses // [] | map(.state.running != null or .state.terminated != null) | any)) ] | length')
    [ "$waiting" -ge 6 ] && break
    sleep 2
  done
  kube -n witness get events -o json >"$LOGS/witness-events-$opt-$run.json" 2>/dev/null || true
  for pod in w-docker-io w-quay-io w-registry-k8s-io w-ghcr-io w-mcr-microsoft-com always; do
    phase=$(kube -n witness get pod "$pod" -o json | jq -r '.status.containerStatuses[0] |
      if .state.running then "running" elif .state.terminated then "terminated"
      else (.state.waiting.reason // "pending") end' 2>/dev/null || echo unknown)
    # The first "Failed to pull" event carries the error; keep its end.
    msg=$(jq -r --arg p "$pod" '[.items[] | select(.involvedObject.name == $p and .reason == "Failed"
      and (.message | startswith("Failed to pull")))] | first | .message // "-"' \
      "$LOGS/witness-events-$opt-$run.json" | sed 's/.*failed to do request: //' | tr '\t\n' '  ' | cut -c1-300)
    tsv witness.tsv "$opt" "$run" "$pod" "$phase" "$msg"
  done
  kube delete namespace witness --wait=true --timeout=120s >>"$LOGS/witness.log" 2>&1 || true
}

record_load() {
  local opt=$1 phase=$2 loadavg others
  loadavg=$(uptime | sed -e 's/.*load average[s]*: //' -e 's/,//g')
  others=$(kind get clusters 2>/dev/null | grep -v "^$NAME\$" | paste -sd, - || true)
  tsv load.tsv "$(utc_now)" "$opt" "$phase" "$loadavg" "$(docker ps -q | wc -l | tr -d ' ')" "${others:--}"
}

record_ports() {
  local opt=$1 name ports
  docker ps --filter "name=$NAME" --format '{{.Names}}\t{{.Ports}}' | while IFS=$'\t' read -r name ports; do
    tsv ports.tsv "$opt" "$name" "${ports:--}"
  done
}

record_volume() {
  local opt=$1 phase=$2 vol
  case $opt in
    keep)
      # kind gives the node an anonymous volume on /var, where containerd
      # keeps its images; the writable layer holds the rest.
      vol=$(docker container inspect -f '{{range .Mounts}}{{if eq .Destination "/var"}}{{.Name}}{{end}}{{end}}' "$NODE")
      tsv volume.tsv "$opt" "$phase" node-var-volume \
        "$(docker system df -v --format '{{json .Volumes}}' | jq -r --arg n "$vol" '.[] | select(.Name == $n) | .Size')"
      tsv volume.tsv "$opt" "$phase" node-writable-layer \
        "$(docker ps -a -s --filter "name=^$NODE\$" --format '{{.Size}}')"
      ;;
    mirror)
      tsv volume.tsv "$opt-$REGISTRY" "$phase" storage-bytes "$(du -sk "$REGISTRY_DIR/storage" | awk '{ print $1 * 1024 }')"
      tsv volume.tsv "$opt-$REGISTRY" "$phase" image-bytes "$(docker image inspect --format '{{.Size}}' "$REG_IMAGE")"
      ;;
    archive)
      tsv volume.tsv "$opt" "$phase" archives-bytes "$(du -sk "$TRIAL_DIR/archives" | awk '{ print $1 * 1024 }')"
      ;;
  esac
}

# --- One run ------------------------------------------------------------------

timed_run() {
  local opt=$1 run=$2 phase=$3 api front t0 t_ready started since_epoch mem pulls kept=created rc=0 up outcome=ready
  api="api-r$run-$(date +%s)"
  front="marker-r$run-$(date +%s)"
  set_markers "$api" "$front"
  if cluster_exists; then kept=kept; fi
  record_load "$opt" "run-$run"
  refresh_lock
  started=$(utc_now)
  since_epoch=$(date +%s)
  log "$opt run $run ($phase, cluster $kept): task up"
  t0=$(now)
  task_up "$opt" "$run"
  t_ready=$(wait_ready "$api" "$front") || rc=$?
  if [ "$rc" = 0 ]; then
    up=$(seconds_between "$t0" "$t_ready")
    log "$opt run $run: ready in $up s"
    if [ "$run" = 1 ]; then record_ports "$opt"; fi
    sleep "$(awk -v t="$t_ready" -v w="$IDLE_WAIT" -v n="$(now)" 'BEGIN { d = t + w - n; printf "%.1f", (d > 0 ? d : 0) }')"
    mem=$(sample_memory "$opt" "$run" rest)
  else
    # Only an offline run may fail: it is the result of test T1 or T2.
    [ "$phase" = offline ] || die "$opt run $run ($phase) not ready (code $rc)"
    up="-"
    mem=$(printf '%s\t%s' "-" "-")
    outcome="not-ready:$(cat "$TRIAL_DIR/pull-failed.tmp" 2>/dev/null || echo timeout)"
    rm -f "$TRIAL_DIR/pull-failed.tmp"
    log "$opt run $run: NOT ready ($outcome)"
    record_failures "$opt" "$run"
  fi
  pulls=$(record_pulls "$opt" "$run" "$started" "$since_epoch")
  record_node_images "$opt" "$run"
  if [ "$opt" = mirror ]; then record_mirror "$opt" "$run" "$started"; fi
  if [ "$phase" = offline ]; then run_witnesses "$opt" "$run"; fi
  log "$opt run $run: task down"
  task_down "$opt" "$run"
  tsv runs.tsv "$opt" "$(variant_name "$opt")" "$run" "$phase" "$kept" "$up" \
    "$(printf '%s' "$mem" | cut -f1)" "$(printf '%s' "$mem" | cut -f2)" "$pulls" "$started" "$outcome"
  held_memory "$opt" "$run"
}

variant_name() {
  case $1 in
    mirror) echo "$REGISTRY" ;;
    archive) echo "${ARCHIVE_VARIANT:--}" ;;
    *) echo "-" ;;
  esac
}

# What stays in memory IDLE_WAIT s after each `task down` (M8): the kept
# node (option keep), the registry (option mirror).
held_memory() {
  local opt=$1 run=$2 i node reg
  [ "$opt" = keep ] || [ "$opt" = mirror ] || return 0
  sleep "$IDLE_WAIT"
  for i in $(seq 1 "$SAMPLES"); do
    node="-"
    reg="-"
    if [ "$opt" = keep ]; then node=$(container_mib "$NODE"); fi
    if [ "$opt" = mirror ]; then reg=$(container_mib "$REG_NAME"); fi
    tsv held.tsv "$opt" "$(variant_name "$opt")" "$run" "$i" "$(utc_now)" "$node" "$reg"
    if [ "$i" -lt "$SAMPLES" ]; then sleep "$SAMPLE_GAP"; fi
  done
}

# Option archive: does `kind load image-archive` accept the sparse archive
# (the index of the registry with the node's platform only)? The answer
# picks the variant of the offline runs.
probe_sparse_archive() {
  local log_file="$LOGS/archive-sparse-probe.log"
  build_archives sparse
  build_archives full
  set_network offline
  create_cluster "$log_file"
  if load_archives sparse "$log_file"; then
    ARCHIVE_VARIANT=sparse
  else
    ARCHIVE_VARIANT=full
  fi
  tsv volume.tsv archive probe sparse-load "$ARCHIVE_VARIANT"
  kube get events -A -o json >"$LOGS/archive-sparse-probe-events.json" 2>/dev/null || true
  kind delete cluster --name "$NAME" --kubeconfig "$KUBECONFIG" >>"$log_file" 2>&1
  log "archive: offline runs use the $ARCHIVE_VARIANT archives"
}

# --- Series -------------------------------------------------------------------

series() {
  local opt=$1 run
  prepare_work
  record_load "$opt" series-start
  case $opt in
    base)
      set_network online
      run=1
      while [ "$run" -le "$RUNS" ]; do
        timed_run base "$run" online
        sleep "$PAUSE_BETWEEN_RUNS"
        run=$((run + 1))
      done
      return 0
      ;;
    keep | archive) set_network online ;;
    mirror)
      # Online phase: run 0 only. Offline phase: runs 1 to RUNS, run 0 was
      # the online phase, with another container on the same storage.
      require_registry "$MIRROR_PHASE"
      set_network mirror
      ;;
  esac
  if [ "$opt" != mirror ] || [ "$MIRROR_PHASE" = online ]; then
    timed_run "$opt" 0 online
    record_volume "$opt" after-run-0
    if [ "$opt" = mirror ]; then return 0; fi
  fi
  case $opt in
    keep) set_network offline ;;
    archive)
      case $ARCHIVE_SOURCE in
        zot) probe_sparse_archive ;;
        docker-save)
          build_docker_save_archives
          set_network offline
          ;;
      esac
      ;;
  esac
  run=1
  while [ "$run" -le "$RUNS" ]; do
    sleep "$PAUSE_BETWEEN_RUNS"
    timed_run "$opt" "$run" offline
    run=$((run + 1))
  done
  record_volume "$opt" end
  if [ "$opt" = keep ]; then
    kind delete cluster --name "$NAME" --kubeconfig "$KUBECONFIG" >>"$LOGS/keep-end.log" 2>&1
  fi
}

# --- Start-up checks ----------------------------------------------------------

check_versions() {
  local v
  for v in docker kind kubectl jq perl openssl shasum du tar; do
    command -v "$v" >/dev/null || die "$v not found"
  done
  v=$(kind version | awk '{ print $2 }')
  [ "$v" = "$KIND_VERSION" ] || die "kind $v found, $KIND_VERSION expected"
  tsv versions.tsv kind "$v"
  v=$(kubectl version --client -o json | jq -r '.clientVersion.minor' | tr -dc '0-9')
  case " $KUBECTL_MINORS " in *" $v "*) ;; *) die "kubectl 1.$v is too far from the kind node (1.36)" ;; esac
  tsv versions.tsv kubectl "$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion')"
  tsv versions.tsv docker "$(docker version --format '{{.Server.Version}}')"
  tsv versions.tsv engine "$(docker info --format '{{.OperatingSystem}} {{.NCPU}} CPU {{.MemTotal}} B {{.Driver}}')"
  tsv versions.tsv host "$(sysctl -n hw.model 2>/dev/null || uname -m) $(sw_vers -productVersion 2>/dev/null || uname -r)"
}

# Every pinned reference of the script appears as is in the stack files.
check_pins() {
  local ref
  for ref in "$SDK_IMAGE" "$ASPNET_IMAGE" "$NGINX_IMAGE" "$BUSYBOX_IMAGE" "$POSTGRES_IMAGE" "$VALKEY_IMAGE"; do
    grep -rqF "${ref#*@sha256:}" "$STACK" || die "digest of $ref not found in $STACK"
  done
  grep -qF "$KIND_IMAGE" "$FILES/kind.yaml" || die "$KIND_IMAGE not found in $FILES/kind.yaml"
}

check_options() {
  local opt
  for opt in $OPTIONS; do
    case $opt in
      base | keep) ;;
      mirror)
        [ "$OPTIONS" = mirror ] || die "option mirror runs alone, in phases (MIRROR_PHASE)"
        case $MIRROR_PHASE in
          online | offline) ;;
          *) die "option mirror needs MIRROR_PHASE=online or offline, after prepare-online or prepare-offline" ;;
        esac
        REG_IMAGE=$(registry_image)
        [ -n "$REGISTRY_DIR" ] && [ -d "$REGISTRY_DIR/config" ] || die "option mirror needs REGISTRY_DIR, written by MIRROR_PHASE=prepare-*"
        REGISTRY_DIR=$(CDPATH='' cd -- "$REGISTRY_DIR" && pwd)
        check_registry
        ;;
      archive)
        case $ARCHIVE_SOURCE in
          docker-save) ;;
          zot) [ -n "$ARCHIVE_SRC" ] && [ -d "$ARCHIVE_SRC" ] || die "ARCHIVE_SOURCE=zot needs ARCHIVE_SRC, the storage of a zot mirror" ;;
          *) die "unknown ARCHIVE_SOURCE: $ARCHIVE_SOURCE" ;;
        esac
        ;;
      *) die "unknown option: $opt" ;;
    esac
  done
}

check_free() {
  if cluster_exists; then die "a kind cluster $NAME already exists"; fi
}

# --- Cleanup ------------------------------------------------------------------

cleanup() {
  local rc=$? ref
  trap - EXIT INT TERM
  set +e
  if [ -n "$TRIAL_DIR" ]; then
    if cluster_exists; then
      log "cleanup: deleting the kind cluster $NAME"
      kind delete cluster --name "$NAME" --kubeconfig "$KUBECONFIG" >>"$LOGS/cleanup.log" 2>&1
    fi
    for ref in $(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E "^$NAME/(api|front):"); do
      docker image rm "$ref" >>"$LOGS/cleanup.log" 2>&1 || log "could not remove $ref"
    done
    if [ "$REG_OURS" = 1 ] && [ "$REGISTRY_REMOVE_AT_EXIT" = 1 ] && registry_exists; then
      log "cleanup: removing $REG_NAME, the registry of this phase (storage kept in $REGISTRY_DIR)"
      docker rm -f "$REG_NAME" >>"$LOGS/cleanup.log" 2>&1
    fi
    if registry_exists; then tsv leftovers.tsv end registry "$REG_NAME" "left in place"; fi
    # By image ID: images pulled by digest only have no tag to list.
    docker image ls -a -q --no-trunc | sort -u >"$TRIAL_DIR/images-after.txt"
    comm -13 "$TRIAL_DIR/images-before.txt" "$TRIAL_DIR/images-after.txt" | while read -r ref; do
      tsv leftovers.tsv end image-new "$ref $(docker image inspect --format '{{.RepoTags}} {{.RepoDigests}} {{.Size}}' "$ref" 2>/dev/null)" "kept in the cache"
    done
    release_lock
    log "results in $TRIAL_DIR"
  fi
  exit "$rc"
}

# Offline runs (online runs for base): how many got ready, and the medians
# of the ready ones. M8 comes from held.tsv: the median of its samples.
summarize() {
  local opt tmp
  tsv summary.tsv option variant runs ready up_s_values up_s_median node_mib_median registry_mib_median held_node_mib held_registry_mib
  for opt in $OPTIONS; do
    tmp="$TRIAL_DIR/summary-$opt.tmp"
    awk -F'\t' -v o="$opt" '$1 == o && $3 != "0" && $3 != "run" { print $2 "\t" $6 "\t" $7 "\t" $8 }' \
      "$TRIAL_DIR/runs.tsv" >"$tmp"
    [ -s "$tmp" ] || continue
    tsv summary.tsv "$opt" "$(cut -f1 "$tmp" | sort -u | paste -sd, -)" "$(grep -c . "$tmp")" \
      "$(cut -f2 "$tmp" | grep -vc '^-$' || true)" "$(cut -f2 "$tmp" | paste -sd, -)" \
      "$(cut -f2 "$tmp" | grep -v '^-$' | median)" "$(cut -f3 "$tmp" | grep -v '^-$' | median)" \
      "$(cut -f4 "$tmp" | grep -v '^-$' | median)" \
      "$(awk -F'\t' -v o="$opt" '$1 == o { print $6 }' "$TRIAL_DIR/held.tsv" | grep -v '^-$' | median)" \
      "$(awk -F'\t' -v o="$opt" '$1 == o { print $7 }' "$TRIAL_DIR/held.tsv" | grep -v '^-$' | median)"
    rm -f "$tmp"
  done
}

# --- Main ---------------------------------------------------------------------

main() {
  local opt
  case $MIRROR_PHASE in
    prepare-online | prepare-offline)
      REG_IMAGE=$(registry_image)
      [ -n "$REGISTRY_DIR" ] || die "MIRROR_PHASE=$MIRROR_PHASE needs REGISTRY_DIR"
      mkdir -p "$REGISTRY_DIR"
      REGISTRY_DIR=$(CDPATH='' cd -- "$REGISTRY_DIR" && pwd)
      prepare_registry "${MIRROR_PHASE#prepare-}"
      exit 0
      ;;
    "" | online | offline) ;;
    *) die "unknown MIRROR_PHASE: $MIRROR_PHASE" ;;
  esac
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
  CERTS="$TRIAL_DIR/certs.d"
  mkdir -p "$LOGS" "$CERTS" "$TRIAL_DIR/archives"
  # The node reads the host directory: it must be traversable.
  chmod 755 "$CERTS"
  export KUBECONFIG="$TRIAL_DIR/kubeconfig"
  : >"$KUBECONFIG"

  tsv runs.tsv option variant run phase cluster up_s node_mib registry_mib pulled present failed docker_pulls started_utc outcome
  tsv samples.tsv option run phase sample utc node_mib registry_mib
  tsv held.tsv option variant run sample utc node_mib registry_mib
  tsv node-images.tsv option run names
  tsv failures.tsv option run pod first_failed_pull
  tsv pulls.tsv option run status image count
  tsv docker-pulls.tsv option run image
  tsv mirror.tsv option run method repo kind status count
  tsv witness.tsv option run pod outcome last_failed_event
  tsv volume.tsv option phase item value detail
  tsv ports.tsv option container ports
  tsv network.tsv utc mode detail
  tsv load.tsv utc option phase loadavg_1_5_15 containers other_clusters
  tsv leftovers.tsv phase type name action
  tsv versions.tsv item version

  # Start-up checks first, without any trap: a refusal deletes nothing.
  check_versions
  check_pins
  check_free
  check_options
  acquire_lock
  docker image ls -a -q --no-trunc | sort -u >"$TRIAL_DIR/images-before.txt"
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  # Checked again with the lock held: another benchmark may have started.
  check_free
  log "trial directory: $TRIAL_DIR"

  for opt in $OPTIONS; do
    series "$opt"
    sleep "$PAUSE_BETWEEN_RUNS"
  done
  summarize
  column -t -s "$(printf '\t')" "$TRIAL_DIR/summary.tsv" >&2 || true
}

main "$@"
