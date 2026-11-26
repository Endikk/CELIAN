#!/usr/bin/env bash
# control: E28
# carries: FR-001, FR-016; contracts/task-cli.md (premier démarrage sans réseau, registre lent ou injoignable); tasks.md, gap 4
#
# The first start without a reachable registry (spec 001, T126): the mirror is
# empty, no public registry answers, task up fails in a bounded time, names
# the registry and says that the first start needs the network.
# - the volume of the mirror is gone (task mirror:purge), and the registries
#   are cut as E10 cuts them (lib/offline.sh), on a copy of the golden repo;
# - task up fails, and ends before OFFLINE_FAIL_LIMIT_SECONDS: it neither
#   waits for the longest timeout of a step nor hangs;
# - its message names the registry, docker.io, and the image that could not
#   be pulled, and says "the first start needs the network" (the mirror holds
#   only what an earlier task up pulled);
# - it creates nothing else on the machine: after task down, no cluster, no
#   mirror container.
# A registry that answers slowly, or that limits pulls, ends the same way after
# the same bounded time; P08 plays that case on a simulated kubectl.
set -uo pipefail
# shellcheck disable=SC1091 # lib/offline.sh is checked on its own
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/offline.sh"

offline_work || exit 2
cleanup() {
  (CDPATH='' cd -- "$E2E_ROOT" && task down >/dev/null 2>&1) || :
  rm -rf "${OFFLINE_WORK:?}"
}
trap cleanup EXIT
offline_copy_repo || {
  fail "could not copy the golden repo into $OFFLINE_WORK"
  e2e_finish
}

# 1. An empty mirror and no registry.
must_succeed down || e2e_finish
must_succeed mirror:purge || e2e_finish
volume_exists "$E2E_VOLUME" && fail "the mirror volume is still there after task mirror:purge: the mirror is not empty"
if ! offline_cut; then
  fail "could not cut the registries in the copy of the golden repo"
  e2e_finish
fi

# 2. task up fails, in a bounded time, and says why.
offline_task "$OFFLINE_FAIL_LIMIT_SECONDS" up
printf 'note: task up ended with status %s after %s s.\n' "$STATUS" "$ELAPSED"
if [ "$STATUS" -eq 0 ]; then
  fail "task up succeeded with an empty mirror and no registry: nothing could have been pulled"
elif [ "$STATUS" -eq 124 ]; then
  fail "task up did not end within $OFFLINE_FAIL_LIMIT_SECONDS s: the wait for a pull is not bounded"
  show_output
fi
case "$OUTPUT" in
  *"docker.io"*) ;;
  *)
    fail "the message of task up does not name the registry, docker.io"
    show_output
    ;;
esac
case "$OUTPUT" in
  *"the first start needs the network"*) ;;
  *)
    fail "the message of task up does not say that the first start needs the network"
    show_output
    ;;
esac
case "$OUTPUT" in
  *"envoyproxy/gateway"*) ;;
  *)
    fail "the message of task up does not name the image that could not be pulled, envoyproxy/gateway"
    show_output
    ;;
esac

# 3. Nothing is left behind by task down.
must_succeed down || e2e_finish
cluster_exists && fail "a cluster $E2E_CLUSTER is left after task down"
container_exists "$E2E_MIRROR" && fail "the mirror container is left after task down"

e2e_finish
