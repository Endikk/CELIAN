#!/usr/bin/env bash
# Runs the tests without a public registry of the current profile, in order,
# then removes the cluster and the mirror container (contracts/task-cli.md,
# `task test:offline`). Called by `task test:offline`, locally and in the job
# offline-lite of CELIAN. PROFILE comes from the environment; the standard
# profile is refused until step 12 of spec 001, so the tests pass PROFILE=lite
# (tasks.md, gap 14).
#
# Same rules as local/tests/e2e/run.sh, whose guard it sources: it refuses to
# start when the cluster, the mirror container or the mirror volume of the
# project already exist (the tests purge the mirror, and remove what they
# find), the tests get a HOME of their own, so that the kubeconfig of the
# project never touches the user's ~/.kube, and DOCKER_CONFIG keeps the
# configuration directory of the docker CLI.
#
# The order: E20 follows the life of the mirror volume, with the network, and
# ends with a started environment; E23 purges the volume and tries the mirror
# under a UID that is not root; E10 purges it again, starts with the network,
# then without a public registry; E28 starts without any, from an empty mirror.
# E10 and E28 cut the registries in a copy of the golden repo (lib/offline.sh),
# never in the real tree.
#
# What stays on the machine afterwards: the mirror volume when the last test
# left it, the node image and the zot image in the cache of the engine, the
# base images of the API and the front.
set -uo pipefail

here="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(CDPATH='' cd -- "$here/../../.." && pwd)"

# Before anything else: no sandbox, no cleanup trap, no call that changes the
# engine (lib/guard.sh of the tests on kind; P07).
# shellcheck disable=SC1091 # lib/guard.sh is checked on its own
. "$here/../e2e/lib/guard.sh"
e2e_guard || {
  printf 'task test:offline shares this guard with task test:e2e: the same names, the same refusal.\n' >&2
  exit 1
}

tests="e20-mirror-volume.sh e23-mirror-nonroot.sh e10-offline-restart.sh first-start-no-registry.sh"

export DOCKER_CONFIG="${DOCKER_CONFIG:-${HOME:?}/.docker}"
sandbox_home="$(mktemp -d)" || exit 2
export HOME="$sandbox_home"
export E2E_SANDBOX_HOME=1
unset KUBECONFIG

cleanup() {
  printf 'Cleanup: task down.\n'
  (CDPATH='' cd -- "$root" && task down) || printf 'Cleanup: task down failed; check kind get clusters and docker ps.\n'
  rm -rf "${sandbox_home:?}"
}
trap cleanup EXIT

failed=""
start="$SECONDS"
for test in $tests; do
  printf '== %s\n' "$test"
  test_start="$SECONDS"
  if bash "$here/$test"; then
    printf '== %s passed in %s s\n' "$test" "$((SECONDS - test_start))"
  else
    printf '== %s FAILED in %s s\n' "$test" "$((SECONDS - test_start))"
    failed="$failed $test"
  fi
done

printf 'Tests without a public registry: %s s in all.\n' "$((SECONDS - start))"
if [ -n "$failed" ]; then
  printf 'Failed:%s\n' "$failed"
  exit 1
fi
printf 'All the tests without a public registry passed.\n'
