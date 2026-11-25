# shellcheck shell=bash
# shellcheck disable=SC2034 # OUTPUT and STATUS are read by the checks of lib/harness.sh
# Shared helpers of the mirror tests: P06, and the launch part of S13
# (spec 001, T042). Sourced, never run. Builds on lib/harness.sh, whose
# sandbox, checks and summary it reuses.
#
# Each case copies local/scripts/mirror.sh, its library and the files it
# reads (local/mirror/, local/kind/) into a project of its own under the
# sandbox, so that a case can take a file away without touching the
# repository. mirror.sh then runs with an empty environment (env -i), a
# temporary HOME, and a PATH that holds bash, sleep, the simulated docker of
# fakes/mirror/, and awk and grep, which that fake uses. No real container
# engine can be reached.

# shellcheck disable=SC1091 # lib/harness.sh is checked on its own
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

MIRROR_SCRIPT_REL="local/scripts/mirror.sh"
MIRROR_FAKE="$PREFLIGHT_ROOT/local/tests/preflight/fakes/mirror/docker"
PROJECT="$SANDBOX/project"
# The zot image of the tests: a tag and a digest, as the Taskfile passes it.
# shellcheck disable=SC2034 # used by the tests that source this file
MIRROR_TEST_IMAGE="ghcr.io/project-zot/zot:v2.1.23@sha256:9d3de83ac2099e6f4843045b4c9b65b7e8baf40f92d28f54906dee9d4d390fd7"

if [ ! -f "$PREFLIGHT_ROOT/$MIRROR_SCRIPT_REL" ]; then
  printf '%s is missing: the mirror of task up is not written yet (spec 001, T049).\n' "$MIRROR_SCRIPT_REL"
  exit 1
fi

# copy_into_project PATH: copies PATH, relative to the golden repo, into the
# project of the sandbox, when it exists.
copy_into_project() {
  [ -e "$PREFLIGHT_ROOT/$1" ] || return 0
  mkdir -p "$PROJECT/$(dirname -- "$1")"
  cp -R "$PREFLIGHT_ROOT/$1" "$PROJECT/$1"
}

# run_mirror_case NAME [--without PATH]... [VAR=value]... [-- ARG...]
#   --without PATH  leaves that file of the project out of the copy
#   VAR=value       environment of mirror.sh: FAKE_* of fakes/mirror/docker
#   ARG             arguments of mirror.sh
# Sets OUTPUT and STATUS, then checks that every docker call was simulated.
run_mirror_case() {
  local path tool
  local -a vars=() without=()
  CASE="$1"
  shift
  CASES=$((CASES + 1))
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --without)
        without+=("$2")
        shift 2
        ;;
      --)
        shift
        break
        ;;
      *=*)
        vars+=("$1")
        shift
        ;;
      *)
        printf 'run_mirror_case "%s": unknown option %s\n' "$CASE" "$1"
        exit 2
        ;;
    esac
  done

  rm -rf "${PROJECT:?}"
  mkdir -p "$PROJECT"
  for path in local/scripts local/mirror local/kind; do
    copy_into_project "$path"
  done
  for path in ${without[@]+"${without[@]}"}; do
    rm -rf "${PROJECT:?}/$path"
  done

  rm -rf "${SANDBOX:?}/bin"
  mkdir "$SANDBOX/bin"
  ln -s "$BASH" "$SANDBOX/bin/bash"
  ln -s "$SLEEP" "$SANDBOX/bin/sleep"
  ln -s "$MIRROR_FAKE" "$SANDBOX/bin/docker"
  for tool in awk grep; do
    ln -s "$(command -v "$tool")" "$SANDBOX/bin/$tool"
  done
  : >"$CALLS"

  STATUS=0
  OUTPUT="$(CDPATH='' cd -- "$SANDBOX" && env -i HOME="$SANDBOX/home" PATH="$SANDBOX/bin" \
    FAKE_LOG="$CALLS" ${vars[@]+"${vars[@]}"} \
    "$BASH" "$PROJECT/$MIRROR_SCRIPT_REL" "$@" 2>&1)" || STATUS=$?
  expect_nothing_created
}

# The docker run of the case, or nothing.
run_line() {
  grep '^docker run ' "$CALLS" || true
}

# expect_no_change: no call that creates, starts or removes anything.
expect_no_change() {
  local changes
  changes="$(grep -E '^docker (run|create|start|container rm|rm|volume create|volume rm|network) ' "$CALLS" | grep -v '^docker network inspect ' || true)"
  [ -z "$changes" ] || fail_case "a call changed the engine: $(printf '%s' "$changes" | tr '\n' ';')"
}

# expect_run_has TEXT: the docker run holds TEXT, between spaces.
expect_run_has() {
  case " $(run_line) " in
    *" $1 "*) ;;
    *) fail_case "the docker run does not hold \"$1\": $(run_line)" ;;
  esac
}

# expect_run_lacks PATTERN: no argument of the docker run matches PATTERN, a
# shell pattern.
expect_run_lacks() {
  local arg
  # shellcheck disable=SC2086 # split the logged line into its arguments
  for arg in $(run_line); do
    # shellcheck disable=SC2254 # the pattern is the point
    case "$arg" in
      $1) fail_case "the docker run holds \"$arg\": $(run_line)" ;;
    esac
  done
}
