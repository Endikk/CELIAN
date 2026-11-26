# shellcheck shell=bash
# The wait for a rollout whose pods pull an image (spec 001, T127; contracts/
# task-cli.md: "Registre public lent ou qui limite", "Premier démarrage sans
# réseau"). Sourced by local/scripts/platform.sh, app.sh and cache.sh, after
# lib/local-env.sh. The caller defines die (its own prefix) and kube (the
# kubectl of the project).
#
# Every wait of task up on a pod goes through wait_rollout, so that none ends
# on a bare timeout of kubectl:
# - it polls the rollout every PULL_POLL_SECONDS, up to the limit its caller
#   gives, which each script names as a constant;
# - a pull error (ErrImagePull, ImagePullBackOff) that lasts
#   PULL_ERROR_SECONDS stops the task at once, and the message names the
#   image, its registry, and says that the first start needs the network: the
#   mirror holds only what an earlier task up pulled (ADR-011), so a first
#   start without the registry, or with one that refuses the pulls, ends here;
# - a pull error that clears within that delay is a retry of the kubelet, not
#   a failure;
# - at the limit, wait_rollout returns 1, after naming on stderr the images
#   that a container still waits for (a slow or limiting registry), so that
#   the caller words the end of its own message.
#
# The pull wait costs nothing on a start that works: the first poll returns
# when the rollout is complete.

# How often the rollout is looked at, and how long a pull error must last
# before it stops the task. The kubelet retries a failed pull with a growing
# delay (ImagePullBackOff, five minutes at most): 60 s covers the first
# retries of a slow registry, and an unreachable one fails from the first try.
readonly PULL_POLL_SECONDS=5
readonly PULL_ERROR_SECONDS=60
# The pause between two polls when kubectl answered at once (a rollout not
# created yet): a poll that waits has no need of it.
readonly PULL_PAUSE_SECONDS=1

# pull_clock: seconds, from any origin. A test replaces it.
pull_clock() {
  printf '%s' "$SECONDS"
}

# registry_of IMAGE: the registry host of an image reference, as Kubernetes
# reads it: the first part when it holds a dot or a colon or is localhost,
# docker.io otherwise.
registry_of() {
  local first="${1%%/*}"
  case "$1" in
    */*)
      case "$first" in
        *.* | *:* | localhost) printf '%s' "$first" ;;
        *) printf 'docker.io' ;;
      esac
      ;;
    *) printf 'docker.io' ;;
  esac
}

# container_states NAMESPACE: one line "<reason> <image>" per container of a
# pod of the namespace that waits, the reason of the wait first. A running
# container gives no line.
container_states() {
  kube --namespace "$1" get pods --output \
    'jsonpath={range .items[*]}{range .status.initContainerStatuses[*]}{.state.waiting.reason}{" "}{.image}{"\n"}{end}{range .status.containerStatuses[*]}{.state.waiting.reason}{" "}{.image}{"\n"}{end}{end}' 2>/dev/null |
    awk 'NF == 2 { print }'
}

# pull_errors NAMESPACE: the "<reason> <image>" lines of the containers whose
# pull fails.
pull_errors() {
  container_states "$1" | awk '$1 == "ErrImagePull" || $1 == "ImagePullBackOff" { print }'
}

# waiting_images NAMESPACE: the lines of the containers still waiting for their
# image or their creation, pull errors included.
waiting_images() {
  container_states "$1" |
    awk '$1 == "ContainerCreating" || $1 == "PodInitializing" || $1 == "ErrImagePull" || $1 == "ImagePullBackOff" { print }'
}

# pull_failure SECONDS LINE...: stops the task with the message of a pull that
# fails: image, registry, the first start, what to do.
pull_failure() {
  local seconds="$1" line="$2" reason image registry
  reason="${line%% *}"
  image="${line#* }"
  registry="$(registry_of "$image")"
  die "the image $image cannot be pulled from the registry $registry ($reason for $seconds s). The mirror holds only what an earlier task up pulled, so the first start needs the network: check the network and whether $registry limits pulls, then run task up again."
}

# wait_rollout NAMESPACE TARGET LIMIT: waits until TARGET (deployment/x or
# statefulset/y) of NAMESPACE is rolled out, LIMIT seconds at most. Returns 0
# when it is, 1 at the limit; stops the task through die on a pull error that
# lasts.
wait_rollout() {
  local namespace="$1" target="$2" limit="$3" start now since=-1 errors last="" waiting
  start="$(pull_clock)"
  while :; do
    if last="$(kube --namespace "$namespace" rollout status "$target" --timeout="${PULL_POLL_SECONDS}s" 2>&1)"; then
      return 0
    fi
    now="$(pull_clock)"
    errors="$(pull_errors "$namespace")"
    if [ -z "$errors" ]; then
      since=-1
    else
      [ "$since" -ge 0 ] || since="$now"
      if [ $((now - since)) -ge "$PULL_ERROR_SECONDS" ]; then
        pull_failure $((now - since)) "$(printf '%s\n' "$errors" | head -n 1)"
      fi
    fi
    if [ $((now - start)) -ge "$limit" ]; then
      break
    fi
    sleep "$PULL_PAUSE_SECONDS"
  done
  [ -z "$last" ] || printf '%s\n' "$last" >&2
  waiting="$(waiting_images "$namespace" | head -n 1)"
  if [ -n "$waiting" ]; then
    printf 'A container still waits for %s, from the registry %s, after %s s: the registry may be slow or limits pulls.\n' \
      "${waiting#* }" "$(registry_of "${waiting#* }")" "$limit" >&2
  fi
  return 1
}
