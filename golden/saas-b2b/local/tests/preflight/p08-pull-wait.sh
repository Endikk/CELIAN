#!/usr/bin/env bash
# control: P08
# carries: FR-001, FR-016; contracts/task-cli.md (registre lent ou injoignable, premier démarrage sans réseau)
#
# The wait for a rollout that pulls an image (local/scripts/lib/pull-wait.sh,
# T127) ends in a bounded time and says why:
# - a rollout that completes returns at once and prints nothing;
# - a pull error (ErrImagePull, ImagePullBackOff) that lasts
#   PULL_ERROR_SECONDS stops the task: the message names the image, its
#   registry (docker.io when the image names none) and says that the first
#   start needs the network, and asks to run task up again;
# - a pull error that clears before that delay does not stop it;
# - a rollout that does not complete within the limit returns 1 so that the
#   caller words its own message; when a container is still waiting for its
#   image, the library says which image and which registry first, on stderr,
#   so that a slow or limiting registry is named;
# - the waits of the scripts are bounded by named constants, none of them
#   hides a bare number (checked on platform.sh, app.sh and cache.sh: each
#   rollout wait goes through wait_rollout).
# kubectl is replaced by a function that answers from the case; the clock
# and sleep are replaced too, so that the control runs in no time and touches
# no cluster. The case numbers poll after poll: nothing is simulated by the
# wall clock.
set -uo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
lib="$root/local/scripts/lib/pull-wait.sh"
failures=0
cases=0

fail() {
  failures=$((failures + 1))
  printf 'FAIL: %s\n' "$1"
}

if [ ! -f "$lib" ]; then
  printf 'local/scripts/lib/pull-wait.sh is missing: the waits of task up do not name a registry that fails to answer (spec 001, T127).\n'
  exit 1
fi

work="$(mktemp -d)" || exit 2
trap 'rm -rf "${work:?}"' EXIT

# The case, read by the functions below: ROLLOUT_AFTER is the poll from which
# the rollout completes (0 never), PODS the lines "<reason> <image>" that
# kubectl prints for the containers, PODS_UNTIL the last poll that shows
# them (0 always).
ROLLOUT_AFTER=0
PODS=""
PODS_UNTIL=0

# shellcheck disable=SC1090 # the library is checked on its own
. "$lib"

# The library calls kube, die, sleep and pull_clock; each is replaced.
polls() { wc -l <"$work/polls" | tr -d ' '; }
kube() {
  local verb
  for verb in "$@"; do
    case "$verb" in
      rollout)
        printf 'x\n' >>"$work/polls"
        if [ "$ROLLOUT_AFTER" -gt 0 ] && [ "$(polls)" -ge "$ROLLOUT_AFTER" ]; then
          return 0
        fi
        printf 'Waiting for deployment "x" rollout to finish\n' >&2
        return 1
        ;;
      pods)
        if [ "$PODS_UNTIL" -eq 0 ] || [ "$(polls)" -le "$PODS_UNTIL" ]; then
          [ -z "$PODS" ] || printf '%s\n' "$PODS"
        fi
        return 0
        ;;
    esac
  done
  return 1
}
sleep() { :; }
pull_clock() { printf '%s' $(($(polls) * PULL_POLL_SECONDS)); }
die() {
  printf 'wait: %s\n' "$1" >&2
  exit 1
}

# run_case NAME LIMIT: runs wait_rollout on a subshell, sets OUTPUT and STATUS.
run_case() {
  cases=$((cases + 1))
  : >"$work/polls"
  STATUS=0
  OUTPUT="$(wait_rollout app deployment/x "$2" 2>&1)" || STATUS=$?
  CASE="$1"
}

expect_status() {
  [ "$STATUS" -eq "$1" ] || {
    fail "$CASE: exit status $STATUS, $1 expected; output: $OUTPUT"
  }
}

expect_text() {
  case "$OUTPUT" in
    *"$1"*) ;;
    *) fail "$CASE: the output does not say: $1 (output: $OUTPUT)" ;;
  esac
}

expect_no_text() {
  case "$OUTPUT" in
    *"$1"*) fail "$CASE: the output says: $1 (output: $OUTPUT)" ;;
  esac
}

expect_polls_at_most() {
  [ "$(polls)" -le "$1" ] || fail "$CASE: $(polls) polls, $1 at most: the wait is not bounded"
}

# 1. A rollout that completes at the first look.
ROLLOUT_AFTER=1 PODS="" PODS_UNTIL=0
run_case "rollout complete" 300
expect_status 0
[ -z "$OUTPUT" ] || fail "$CASE: prints \"$OUTPUT\", nothing expected"

# 2. A pull error that lasts: the first start needs the network, the registry
# is named.
ROLLOUT_AFTER=0 PODS="ImagePullBackOff docker.io/envoyproxy/gateway:v1.10.0@sha256:c2243d43518bed91d3ed8c2db849a4b7a14ac9b96eb019f2ab104bb1ca8572b1" PODS_UNTIL=0
run_case "pull error that lasts" 300
expect_status 1
expect_text "docker.io"
expect_text "envoyproxy/gateway:v1.10.0"
expect_text "the first start needs the network"
expect_text "task up"
expect_polls_at_most $((PULL_ERROR_SECONDS / PULL_POLL_SECONDS + 3))

# 3. An image with no registry in its name comes from docker.io.
ROLLOUT_AFTER=0 PODS="ErrImagePull postgres:18.7-trixie" PODS_UNTIL=0
run_case "image without a registry" 300
expect_status 1
expect_text "docker.io"

# 4. Another registry is named as it is written, port included.
ROLLOUT_AFTER=0 PODS="ErrImagePull ghcr.io:443/fluxcd/source-controller:v1" PODS_UNTIL=0
run_case "registry with a port" 300
expect_status 1
expect_text "ghcr.io:443"

# 5. A pull error that clears before the delay does not stop the wait.
ROLLOUT_AFTER=6 PODS="ErrImagePull docker.io/library/postgres:18.7-trixie" PODS_UNTIL=3
run_case "pull error that clears" 300
expect_status 0

# 6. A container that waits for its image up to the limit: the caller words
# the message, the library names the image and the registry on stderr.
ROLLOUT_AFTER=0 PODS="ContainerCreating docker.io/valkey/valkey:9.1.4-alpine" PODS_UNTIL=0
run_case "slow pull up to the limit" 60
expect_status 1
expect_text "docker.io"
expect_text "valkey/valkey"
expect_text "slow or limits pulls"
expect_polls_at_most $((60 / PULL_POLL_SECONDS + 3))

# 7. A rollout that fails for another reason: returns 1, names no registry.
ROLLOUT_AFTER=0 PODS="" PODS_UNTIL=0
run_case "other failure up to the limit" 60
expect_status 1
expect_no_text "registry"
expect_polls_at_most $((60 / PULL_POLL_SECONDS + 3))

# 8. The waits of the scripts: each rollout wait of platform.sh, app.sh and
# cache.sh goes through wait_rollout, and none calls kubectl rollout status
# on its own.
for script in platform.sh app.sh cache.sh; do
  cases=$((cases + 1))
  if grep -n -E '(^|[^_a-z])kube(_ns)?( .*)? rollout status' "$root/local/scripts/$script" >/dev/null; then
    fail "local/scripts/$script calls kubectl rollout status itself: use wait_rollout of lib/pull-wait.sh (T127)"
  fi
  if ! grep -q 'pull-wait.sh' "$root/local/scripts/$script"; then
    fail "local/scripts/$script does not source lib/pull-wait.sh (T127)"
  fi
done

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s) in %s case(s).\n' "$failures" "$cases"
  exit 1
fi
printf 'passed, %s cases.\n' "$cases"
