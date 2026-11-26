#!/usr/bin/env bash
# Runs the tests on kind of the current profile, in order, then removes the
# cluster and the mirror container (contracts/task-cli.md, `task test:e2e`:
# "cluster créé et supprimé"). Called by `task test:e2e`, locally and in the
# job e2e-lite of CELIAN. PROFILE comes from the environment; the standard
# profile is refused until step 12 of spec 001, so the tests pass
# PROFILE=lite (tasks.md, gap 14).
#
# It refuses to start when the cluster, the mirror container or the mirror
# volume of the project already exist: it would remove what it did not create.
# The CI runner is new and has none of them.
#
# The tests get a HOME of their own, so that the kubeconfig of the project
# and the decoys of E24 never touch the user's ~/.kube. DOCKER_CONFIG keeps
# the configuration directory of the docker CLI, and with it the current
# context (docker reference, environment variables). Each test removes what
# it created besides the tasks: decoy containers and volumes of E22 and E08.
#
# What stays on the machine afterwards: the mirror volume when the last test
# left it, the node image and the zot image in the cache of the engine.
set -uo pipefail

here="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(CDPATH='' cd -- "$here/../../.." && pwd)"

# Before anything else: no sandbox, no cleanup trap, no call that changes the
# engine. The tests remove what they find under the names of the development
# environment, so they never start over it (lib/guard.sh; P07).
# shellcheck disable=SC1091 # lib/guard.sh is checked on its own
. "$here/lib/guard.sh"
e2e_guard || exit 1

# The order matters: E24 starts the environment with a decoy kubeconfig set;
# E05, E12 and E06 work on that environment; E21 breaks it and ends with
# task down; E04 starts two new environments; E08 ends with task down and
# task mirror:purge.
tests="e24-decoy-kubeconfig.sh e19-kubeconfig.sh e03-loopback.sh e05-secrets-kept.sh e12-postgres.sh"
tests="$tests e06-secrets-not-in-repo.sh e21-volume-without-secrets.sh e04-secrets-fresh.sh"
tests="$tests e22-foreign-container.sh e08-down.sh"

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

printf 'Tests on kind: %s s in all.\n' "$((SECONDS - start))"
if [ -n "$failed" ]; then
  printf 'Failed:%s\n' "$failed"
  exit 1
fi
printf 'All the tests on kind passed.\n'
