# shellcheck shell=bash
# Shared helpers of the preflight tests P01 to P05 (spec 001, T034). Sourced
# by each test, never run on its own: it lives in lib/ so that
# tests/run-static.sh, which runs every *.sh of local/tests/preflight/, does
# not take it for a control.
#
# Each case runs local/scripts/preflight.sh in a sandbox: an empty
# environment (env -i), a temporary HOME, and a PATH that holds bash and the
# simulated binaries of fakes/ only. No real container engine, kind or
# kubectl can be reached, and a tool left out of PATH is truly absent. The
# fakes log every call; a call they do not simulate fails and is logged as
# UNEXPECTED. Every case checks that none happened, so that a refusal is
# also proven to come before anything is created.

PREFLIGHT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
PREFLIGHT="$PREFLIGHT_ROOT/local/scripts/preflight.sh"
FAKES_DIR="$PREFLIGHT_ROOT/local/tests/preflight/fakes"
ALL_FAKES="docker kind kubectl uname"

# Memory sizes handed to the fake docker by the tests, in bytes.
# shellcheck disable=SC2034 # used by the tests that source this file
MIB=1048576
# shellcheck disable=SC2034 # used by the tests that source this file
GIB=1073741824

if [ ! -f "$PREFLIGHT" ]; then
  printf 'local/scripts/preflight.sh is missing: the preflight checks of task up are not written yet (spec 001, T037).\n'
  exit 1
fi

SANDBOX="$(mktemp -d)"
trap 'rm -rf "${SANDBOX:?}"' EXIT
mkdir "$SANDBOX/home"
CALLS="$SANDBOX/calls.log"

CASE=""
CASES=0
FAILURES=0
CASE_SHOWN=""
OUTPUT=""
STATUS=0

# Body run by "bash -c" for --taken: sources preflight.sh, which then does
# not run main, replaces port_in_use, then runs main. A TCP listener cannot
# be simulated through PATH, and opening one would need a tool that the
# machine may not have.
# shellcheck disable=SC2016 # expanded by the inner bash, not here
STUB_RUNNER='source "$1"
shift
port_in_use() {
  case " $FAKE_TAKEN_PORTS " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}
main "$@"'

# run_case NAME [--without TOOL]... [--taken PORTS] [VAR=value]... [-- ARG...]
#   --without TOOL  leaves that simulated binary out of PATH
#   --taken PORTS   replaces the TCP probe: PORTS, separated by spaces, are
#                   in use, every other port is free
#   VAR=value       environment of preflight.sh: FAKE_*, PROFILE, KUBECONFIG
#   ARG             arguments of preflight.sh, the host ports to check
# Sets OUTPUT (stdout and stderr) and STATUS, then checks that nothing was
# created.
run_case() {
  local without="" taken="" use_stub=0 tool
  local -a vars=()
  CASE="$1"
  shift
  CASES=$((CASES + 1))
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --without)
        without="$without $2"
        shift 2
        ;;
      --taken)
        use_stub=1
        taken="$2"
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
        printf 'run_case "%s": unknown option %s\n' "$CASE" "$1"
        exit 2
        ;;
    esac
  done

  rm -rf "${SANDBOX:?}/bin"
  mkdir "$SANDBOX/bin"
  ln -s "$BASH" "$SANDBOX/bin/bash"
  for tool in $ALL_FAKES; do
    case " $without " in
      *" $tool "*) continue ;;
    esac
    ln -s "$FAKES_DIR/$tool" "$SANDBOX/bin/$tool"
  done
  : >"$CALLS"

  STATUS=0
  if [ "$use_stub" -eq 1 ]; then
    OUTPUT="$(cd "$SANDBOX" && env -i HOME="$SANDBOX/home" PATH="$SANDBOX/bin" \
      FAKE_LOG="$CALLS" FAKE_TAKEN_PORTS="$taken" ${vars[@]+"${vars[@]}"} \
      "$BASH" -c "$STUB_RUNNER" preflight "$PREFLIGHT" "$@" 2>&1)" || STATUS=$?
  else
    OUTPUT="$(cd "$SANDBOX" && env -i HOME="$SANDBOX/home" PATH="$SANDBOX/bin" \
      FAKE_LOG="$CALLS" ${vars[@]+"${vars[@]}"} \
      "$BASH" "$PREFLIGHT" "$@" 2>&1)" || STATUS=$?
  fi
  expect_nothing_created
}

# begin_check NAME: a case checked by the test itself, without a run.
begin_check() {
  CASE="$1"
  CASES=$((CASES + 1))
  OUTPUT=""
  STATUS=0
}

fail_case() {
  FAILURES=$((FAILURES + 1))
  printf 'case "%s": %s\n' "$CASE" "$1"
  if [ "$CASE_SHOWN" != "$CASE" ]; then
    CASE_SHOWN="$CASE"
    printf '  exit status %s, output:\n' "$STATUS"
    printf '%s\n' "$OUTPUT" | sed 's/^/    /'
  fi
}

# The checks passed: exit status 0.
expect_ok() {
  [ "$STATUS" -eq 0 ] || fail_case "expected the checks to pass"
}

# A refusal of preflight.sh: exit status 1, not a crash.
expect_refused() {
  [ "$STATUS" -eq 1 ] || fail_case "expected a refusal (exit status 1)"
}

expect_output() {
  case "$OUTPUT" in
    *"$1"*) ;;
    *) fail_case "the output does not say: $1" ;;
  esac
}

expect_no_output() {
  case "$OUTPUT" in
    *"$1"*) fail_case "the output should not say: $1" ;;
  esac
}

expect_nothing_created() {
  if grep -q '^UNEXPECTED' "$CALLS"; then
    fail_case "a call that the fakes do not simulate was made: $(grep '^UNEXPECTED' "$CALLS" | tr '\n' ';')"
  fi
}

# expect_called LINE: the fakes logged exactly this call.
expect_called() {
  grep -qxF -e "$1" "$CALLS" || fail_case "call not made: $1"
}

# expect_not_called TOOL: no call to that tool at all.
expect_not_called() {
  if grep -q "^$1 " "$CALLS"; then
    fail_case "$1 should not be called: $(grep "^$1 " "$CALLS" | tr '\n' ';')"
  fi
}

# expect_only_call TOOL LINE: every call to TOOL is exactly LINE.
expect_only_call() {
  local other
  other="$(grep "^$1 " "$CALLS" | grep -vxF -e "$2" || true)"
  [ -z "$other" ] || fail_case "unexpected $1 call: $(printf '%s' "$other" | tr '\n' ';')"
}

finish() {
  if [ "$FAILURES" -gt 0 ]; then
    printf '%s failure(s) in %s case(s).\n' "$FAILURES" "$CASES"
    exit 1
  fi
  printf '%s case(s) passed.\n' "$CASES"
}
