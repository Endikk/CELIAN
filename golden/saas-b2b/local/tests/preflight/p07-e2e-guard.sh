#!/usr/bin/env bash
# control: P07
# carries: FR-007; ADR-011, condition 11; contracts/task-cli.md (task test:e2e)
#
# task test:e2e never removes what it did not create. The tests on kind use
# the names of the development environment (cluster saas-b2b, container and
# volume saas-b2b-mirror); one of E24 reuses a cluster that exists, the
# cleanup of run.sh runs task down, and E08 runs task mirror:purge. So
# local/tests/e2e/run.sh refuses to start, with a message that names what
# exists, when the cluster, the container or the volume is already there, and
# before it creates the sandbox HOME or installs the cleanup. A neighbour of
# a close name, such as saas-b2b-other, does not count. The CI runner is
# new and has none of them. Simulated docker and kind only (fakes/e2e/).
# shellcheck disable=SC2034 # CASE, OUTPUT and STATUS are read by the checks of lib/harness.sh
set -uo pipefail
# shellcheck disable=SC1091 # lib/harness.sh is checked on its own
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

RUN_SCRIPT="$PREFLIGHT_ROOT/local/tests/e2e/run.sh"
GUARD_LIB="$PREFLIGHT_ROOT/local/tests/e2e/lib/guard.sh"
E2E_FAKES="$FAKES_DIR/e2e"

# run_guard NAME [VAR=value]...: runs run.sh with the simulated docker and kind,
# and a PATH that holds nothing else the tests could use: no task, no kubectl.
# Sets OUTPUT and STATUS.
run_guard() {
  local tool
  local -a vars=()
  CASE="$1"
  shift
  CASES=$((CASES + 1))
  vars=("$@")
  rm -rf "${SANDBOX:?}/bin"
  mkdir "$SANDBOX/bin"
  ln -s "$BASH" "$SANDBOX/bin/bash"
  ln -s "$E2E_FAKES/docker" "$SANDBOX/bin/docker"
  ln -s "$E2E_FAKES/kind" "$SANDBOX/bin/kind"
  for tool in dirname mktemp rm grep awk; do
    ln -s "$(command -v "$tool")" "$SANDBOX/bin/$tool"
  done
  : >"$CALLS"
  STATUS=0
  OUTPUT="$(CDPATH='' cd -- "$SANDBOX" && env -i HOME="$SANDBOX/home" PATH="$SANDBOX/bin" \
    FAKE_LOG="$CALLS" ${vars[@]+"${vars[@]}"} "$BASH" "$RUN_SCRIPT" 2>&1)" || STATUS=$?
  expect_nothing_created
}

# expect_guard_refusal TEXT: run.sh refused, named TEXT, and started no test.
expect_guard_refusal() {
  expect_refused
  expect_output "$1"
  expect_output "task test:e2e"
  expect_no_output "== "
  expect_no_output "Cleanup"
  expect_not_called "docker run"
  expect_not_called "docker volume rm"
  expect_not_called "docker container rm"
  expect_not_called "kind delete"
  expect_not_called "kind create"
}

run_guard "development cluster there: refused" FAKE_E2E_CLUSTER=present
expect_guard_refusal "cluster saas-b2b"

run_guard "development mirror container there: refused" FAKE_E2E_CONTAINER=present
expect_guard_refusal "container saas-b2b-mirror"

run_guard "development mirror volume there: refused" FAKE_E2E_VOLUME=present
expect_guard_refusal "volume saas-b2b-mirror"

run_guard "all three there: all three named" \
  FAKE_E2E_CLUSTER=present FAKE_E2E_CONTAINER=present FAKE_E2E_VOLUME=present
expect_guard_refusal "cluster saas-b2b"
expect_output "container saas-b2b-mirror"
expect_output "volume saas-b2b-mirror"

run_guard "kind cannot reach the engine: refused, nothing assumed" FAKE_E2E_CLUSTER=broken
expect_guard_refusal "cannot check"

# The guard alone, with nothing in the way, and with a neighbour of a close
# name: it passes without a word and calls nothing but the inspections.
# shellcheck disable=SC2016 # the script of bash -c is expanded by the inner bash
guard_alone() {
  local tool
  CASE="$1"
  shift
  CASES=$((CASES + 1))
  rm -rf "${SANDBOX:?}/bin"
  mkdir "$SANDBOX/bin"
  ln -s "$BASH" "$SANDBOX/bin/bash"
  ln -s "$E2E_FAKES/docker" "$SANDBOX/bin/docker"
  ln -s "$E2E_FAKES/kind" "$SANDBOX/bin/kind"
  ln -s "$(command -v grep)" "$SANDBOX/bin/grep"
  : >"$CALLS"
  STATUS=0
  OUTPUT="$(CDPATH='' cd -- "$SANDBOX" && env -i HOME="$SANDBOX/home" PATH="$SANDBOX/bin" \
    FAKE_LOG="$CALLS" "$@" "$BASH" -c '. "$1" && e2e_guard' guard "$GUARD_LIB" 2>&1)" || STATUS=$?
  expect_nothing_created
}

guard_alone "nothing in the way: passes" FAKE_E2E_CLUSTER=absent
expect_ok
expect_no_output "saas-b2b"

guard_alone "a cluster of a close name does not count" FAKE_E2E_CLUSTER=neighbour
expect_ok

finish
