#!/usr/bin/env bash
# The zot mirror of the local cluster (ADR-011; spec 001, plan, "Ce que fait
# task up", point 3; contracts/task-cli.md).
#
# Usage: bash local/scripts/mirror.sh check IMAGE | up IMAGE | down | report IMAGE | purge | size
#   check   the checks of up that need no cluster (image, configuration,
#           container, volume): task up runs them before it creates the
#           cluster, and creates nothing
#   up      runs check and looks for the network kind, removes an old mirror
#           container of the project, then starts the mirror on the network
#           kind with no published port, the configuration read-only and the
#           volume of the project, and waits until it runs
#   down    removes the mirror container of the project, and only it
#   report  shows what stays on the machine after task down
#   size    prints the size of the mirror volume, as task up ends with it
#   purge   says that the next task up will need the network, then removes
#           the mirror volume of the project, and only it
#   IMAGE   the zot image, by tag and digest: MIRROR_IMAGE of
#           local/tasks/local.yml
#
# A container or a volume is removed or reused only when its name, its
# label and, for a container, the repository of its image are the
# project's (ADR-011, condition 11); anything else is left alone and named.
# The mirror has no authentication (R-34): it publishes no port, joins the
# network kind alone, and stops at each task down. Readiness: zot reads its
# configuration and binds its port at start, and exits at once when either
# fails; the script waits until the container runs and still runs a moment
# later (research RS-13). Commands that create or remove something are
# listed at the head of Taskfile.yml.
set -euo pipefail

here="${BASH_SOURCE[0]}"
case "$here" in
  */*) here="${here%/*}" ;;
  *) here="." ;;
esac
# shellcheck disable=SC1091 # lib/local-env.sh is checked on its own
. "$here/lib/local-env.sh"
root="$(CDPATH='' cd -- "$here/../.." && pwd)"

# The configuration of the project, mounted read-only where the command of
# the image, serve /etc/zot/config.json, reads it (ADR-011, condition 7).
readonly CONFIG_FILE="$root/local/mirror/zot/config.json"
readonly CONFIG_IN_CONTAINER="/etc/zot/config.json"
# storage.rootDirectory of the configuration: the volume goes there, out of
# the project tree (ADR-011, condition 9). It is the home folder of the
# nonroot user of the image (the distroless base owns it for UID 65532): a new
# named volume takes the content and the owner of the folder it covers, so
# zot, which runs as MIRROR_USER of lib/local-env.sh, can write it. A volume
# mounted on a folder that the image does not have is created owned by root,
# and zot then fails every write with "permission denied" (E23, tasks.md,
# gap 166).
readonly STORAGE_IN_CONTAINER="/home/nonroot"
# How long the mirror gets to reach the state running, then how long it must
# keep it. BENCH-010 did not measure its start (ADR-011); zot started in
# less than a second on the measurement machine (research RS-13).
readonly START_SECONDS=30
readonly SETTLE_SECONDS=2
# Log lines shown when the mirror stops.
readonly LOG_LINES=20
# Log lines read to look for a write error: zot logs it within its first lines.
readonly LOG_LINES_CHECKED=200
readonly KIND_CONFIG="$root/local/kind/cluster.yaml"

die() {
  printf 'mirror: %s\n' "$1" >&2
  exit 1
}

# image_ok IMAGE: the zot repository, a tag, and a digest of 64 hex digits.
image_ok() {
  [[ $1 =~ ^${MIRROR_REPOSITORY//./\\.}:[A-Za-z0-9._-]+@sha256:[a-f0-9]{64}$ ]]
}

# container_owner: prints "<label>|<image>" of the container named
# MIRROR_CONTAINER, or fails when there is none.
container_owner() {
  docker container inspect \
    --format "{{index .Config.Labels \"$OWNER_LABEL_KEY\"}}|{{.Config.Image}}" \
    "$MIRROR_CONTAINER" 2>/dev/null
}

# is_ours "<label>|<image>": the label of the mirror, and an image of the
# zot repository, whatever its digest: an older digest is the project's too.
is_ours() {
  local label="${1%%|*}" image="${1#*|}"
  [ "$label" = "$MIRROR_ROLE" ] || return 1
  case "$image" in
    "$MIRROR_REPOSITORY":* | "$MIRROR_REPOSITORY"@*) return 0 ;;
  esac
  return 1
}

foreign_container() {
  printf 'the container %s is not the mirror of this project (label %s=%s and an image of %s expected, found %s): it is left alone. Remove or rename it yourself if it is no longer needed.' \
    "$MIRROR_CONTAINER" "$OWNER_LABEL_KEY" "$MIRROR_ROLE" "$MIRROR_REPOSITORY" "$1"
}

# remove_container: removes the mirror container of the project, if any.
# Returns 1, with a message on stderr, when a container of that name is not
# the project's.
remove_container() {
  local owner
  owner="$(container_owner)" || return 0
  if ! is_ours "$owner"; then
    printf 'mirror: %s\n' "$(foreign_container "$owner")" >&2
    return 1
  fi
  docker container rm --force "$MIRROR_CONTAINER" >/dev/null
  printf 'Mirror: container %s removed.\n' "$MIRROR_CONTAINER"
}

# volume_label: the label of the mirror volume, or fails when there is none.
volume_label() {
  docker volume inspect --format "{{index .Labels \"$OWNER_LABEL_KEY\"}}" "$MIRROR_VOLUME" 2>/dev/null
}

# show_logs: the last lines of the mirror, on stderr, for a failure.
show_logs() {
  docker logs --tail "$LOG_LINES" "$MIRROR_CONTAINER" >&2 || :
}

# mirror_status: the state of the mirror container, running when all is well.
mirror_status() {
  local state
  state="$(docker container inspect --format '{{.State.Status}}' "$MIRROR_CONTAINER")"
  printf '%s' "${state%%|*}"
}

# wait_ready: no published port, no shell in the image for a health check
# (--health-cmd runs one) and no docker exec: the HTTP answer of the mirror
# cannot be asked from the machine (research RS-13). The script waits until
# the container runs, then checks that it still runs SETTLE_SECONDS later.
wait_ready() {
  local status waited=0
  while :; do
    status="$(mirror_status)"
    case "$status" in
      running) break ;;
      created | restarting) ;;
      *)
        show_logs
        die "the mirror $MIRROR_CONTAINER is $status; its last log lines are above."
        ;;
    esac
    if [ "$waited" -ge "$START_SECONDS" ]; then
      show_logs
      die "the mirror $MIRROR_CONTAINER does not run within $START_SECONDS s; its last log lines are above."
    fi
    sleep 1
    waited=$((waited + 1))
  done
  sleep "$SETTLE_SECONDS"
  status="$(mirror_status)"
  if [ "$status" != running ]; then
    show_logs
    die "the mirror $MIRROR_CONTAINER stopped right after its start, now $status; its last log lines are above."
  fi
  check_writable
}

# check_writable: zot runs as a user that is not root and keeps running when
# it cannot write its volume: it answers every pull with an error, and the
# node then falls back to the public registry, so a mirror that stays empty
# goes unseen until the network is cut. A volume that an earlier task up made
# for root, or a folder of the image that another user owns, shows at the
# start of zot as "permission denied" in its log (E23, tasks.md, gap 167).
check_writable() {
  local lines
  lines="$(docker logs --tail "$LOG_LINES_CHECKED" "$MIRROR_CONTAINER" 2>&1)" || lines=""
  case "$lines" in
    *"permission denied"*)
      show_logs
      die "the mirror $MIRROR_CONTAINER cannot write its volume $MIRROR_VOLUME (permission denied, in its log above): the volume was made for another user, by an earlier task up. Run task down, then task mirror:purge, then task up again: the next task up needs the network."
      ;;
  esac
}

# check IMAGE: everything that can be checked before the cluster exists, so that
# task up refuses at once and not after 30 to 75 s of cluster creation
# (contracts/task-cli.md, checks before creation): the image, the
# configuration, the container and the volume of the mirror name. It creates
# and removes nothing. The network kind is left to up: kind creates it.
check() {
  local image="${1:-}" label owner
  if ! image_ok "$image"; then
    die "\"$image\" is not an image of $MIRROR_REPOSITORY by tag and digest: run the mirror through task up, which passes MIRROR_IMAGE of local/tasks/local.yml. Nothing was created."
  fi
  if [ ! -f "$CONFIG_FILE" ]; then
    die "$CONFIG_FILE is missing: the mirror never starts without the configuration of the project (ADR-011, condition 7). Restore it from the repository. Nothing was created."
  fi
  if owner="$(container_owner)" && ! is_ours "$owner"; then
    die "$(foreign_container "$owner") Nothing was created."
  fi
  if label="$(volume_label)" && [ "$label" != "$MIRROR_ROLE" ]; then
    die "a volume $MIRROR_VOLUME exists without the label $OWNER_LABEL_KEY=$MIRROR_ROLE: it is not the mirror volume of this project, and is left alone. Nothing was created."
  fi
}

up() {
  local image="${1:-}"
  check "$image"
  if ! docker network inspect --format '{{.Name}}' "$KIND_NETWORK" >/dev/null 2>&1; then
    die "the network $KIND_NETWORK does not exist: the cluster creates it, run task up. Nothing was created."
  fi
  if ! volume_label >/dev/null; then
    docker volume create --label "$OWNER_LABEL_KEY=$MIRROR_ROLE" "$MIRROR_VOLUME" >/dev/null
    printf 'Mirror: volume %s created.\n' "$MIRROR_VOLUME"
  fi
  remove_container
  docker run --detach --name "$MIRROR_CONTAINER" --label "$OWNER_LABEL_KEY=$MIRROR_ROLE" \
    --network "$KIND_NETWORK" \
    --mount "type=bind,src=$CONFIG_FILE,dst=$CONFIG_IN_CONTAINER,readonly" \
    --mount "type=volume,src=$MIRROR_VOLUME,dst=$STORAGE_IN_CONTAINER" \
    --user "$MIRROR_USER" --cap-drop ALL --security-opt no-new-privileges=true --read-only \
    "$image" serve "$CONFIG_IN_CONTAINER" >/dev/null
  wait_ready
  printf 'Mirror: container %s runs on the network %s, no published port, volume %s.\n' \
    "$MIRROR_CONTAINER" "$KIND_NETWORK" "$MIRROR_VOLUME"
}

down() {
  # A container of that name that is not the project's is named and left
  # alone; task down goes on and deletes the cluster.
  remove_container || :
}

# volume_size: the size of the mirror volume as docker system df shows it.
volume_size() {
  local entry volumes
  volumes="$(docker system df -v --format '{{range .Volumes}}{{.Name}}={{.Size}};{{end}}')"
  for entry in ${volumes//;/ }; do
    if [ "${entry%%=*}" = "$MIRROR_VOLUME" ]; then
      printf '%s' "${entry#*=}"
      return 0
    fi
  done
  printf 'unknown size'
}

# The node image, as local/kind/cluster.yaml names it.
node_image() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *"image: "*)
        printf '%s' "${line##*image: }"
        return 0
        ;;
    esac
  done <"$KIND_CONFIG"
}

# cached IMAGE: "kept" when the engine holds IMAGE, "absent" otherwise.
cached() {
  if docker image inspect --format '{{.Id}}' "$1" >/dev/null 2>&1; then
    printf 'kept'
  else
    printf 'absent'
  fi
}

report() {
  local image="${1:-}" node label
  node="$(node_image)"
  printf 'What stays on this machine:\n'
  if label="$(volume_label)" && [ "$label" = "$MIRROR_ROLE" ]; then
    printf '  - volume %s, %s: the images that the mirror serves. task mirror:purge removes it; the next task up then needs the network.\n' \
      "$MIRROR_VOLUME" "$(volume_size)"
  else
    printf '  - no mirror volume.\n'
  fi
  [ -z "$node" ] || printf '  - node image %s in the cache of the engine: %s.\n' "$node" "$(cached "$node")"
  [ -z "$image" ] || printf '  - mirror image %s in the cache of the engine: %s.\n' "$image" "$(cached "$image")"
  printf '  The base images of the API and the front stay there too, from step 9 on. docker image rm removes an image of the cache.\n'
}

size() {
  printf 'Mirror volume %s: %s.\n' "$MIRROR_VOLUME" "$(volume_size)"
}

purge() {
  local label
  printf 'Mirror: the next task up will need the network, to fill the mirror again.\n'
  if container_owner >/dev/null; then
    die "a container $MIRROR_CONTAINER exists and holds the volume: run task down first, then task mirror:purge."
  fi
  if ! label="$(volume_label)"; then
    printf 'Mirror: no mirror volume %s, nothing to remove.\n' "$MIRROR_VOLUME"
    return 0
  fi
  [ "$label" = "$MIRROR_ROLE" ] ||
    die "the volume $MIRROR_VOLUME has not the label $OWNER_LABEL_KEY=$MIRROR_ROLE: it is not the mirror volume of this project, and is left alone."
  docker volume rm "$MIRROR_VOLUME" >/dev/null
  printf 'Mirror: volume %s removed.\n' "$MIRROR_VOLUME"
}

case "${1:-}" in
  check)
    check "${2:-}"
    printf 'Mirror: image, configuration, container and volume checked, nothing created.\n'
    ;;
  up) up "${2:-}" ;;
  down) down ;;
  report) report "${2:-}" ;;
  purge) purge ;;
  size) size ;;
  *) die "usage: bash local/scripts/mirror.sh check IMAGE | up IMAGE | down | report IMAGE | purge | size" ;;
esac
