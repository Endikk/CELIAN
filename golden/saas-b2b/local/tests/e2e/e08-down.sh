#!/usr/bin/env bash
# control: E08
# carries: FR-007, FR-016; ADR-011, conditions 5 and 11; contracts/task-cli.md
#
# Part of E08 that step 6 can check (tasks.md, gaps 2 and 12): task down and
# task mirror:purge. Step 9 adds task app:down (T084).
# - task down removes the cluster and the mirror container, keeps the mirror
#   volume, and shows what stays on the machine: the volume with its size,
#   and the command that removes it;
# - task mirror:purge refuses while the mirror runs; once it is down, it
#   says first that the next task up will need the network, then removes
#   the mirror volume and no other, even one of a close name with the label
#   of the project.
set -uo pipefail
# shellcheck disable=SC1091 # lib/e2e.sh is checked on its own
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/e2e.sh"

decoy_volume="$E2E_VOLUME-decoy"
decoy_created=no
remove_decoy() {
  if [ "$decoy_created" = yes ]; then
    docker volume rm "$decoy_volume" >/dev/null 2>&1 || printf 'E08: could not remove the decoy volume %s.\n' "$decoy_volume"
  fi
}
trap remove_decoy EXIT

must_succeed up || e2e_finish

run_task mirror:purge
if [ "$STATUS" -eq 0 ]; then
  fail "task mirror:purge succeeded while the mirror runs"
fi
volume_exists "$E2E_VOLUME" || fail "task mirror:purge removed the volume of a running mirror"
expect_output "task down"

must_succeed down
cluster_exists && fail "task down left the cluster $E2E_CLUSTER"
container_exists "$E2E_MIRROR" && fail "task down left the mirror container $E2E_MIRROR"
volume_exists "$E2E_VOLUME" || fail "task down removed the mirror volume $E2E_VOLUME"
[ -e "$E2E_KUBECONFIG" ] && fail "task down left the kubeconfig of the removed cluster, $E2E_KUBECONFIG"
expect_output "$E2E_VOLUME"
expect_output "task mirror:purge"
size_line="${E2E_VOLUME}[^"$'\n'"]*[0-9.]+ ?[kMGT]?B"
if ! [[ $OUTPUT =~ $size_line ]]; then
  fail "task down does not show the size of the mirror volume"
  show_output
fi

if docker volume create --label "$E2E_LABEL" "$decoy_volume" >/dev/null; then
  decoy_created=yes
else
  fail "could not create the decoy volume $decoy_volume"
fi

must_succeed mirror:purge
first_line="${OUTPUT%%$'\n'*}"
case "$first_line" in
  *network*) ;;
  *) fail "task mirror:purge does not say first that the next task up needs the network: $first_line" ;;
esac
volume_exists "$E2E_VOLUME" && fail "task mirror:purge left the mirror volume $E2E_VOLUME"
volume_exists "$decoy_volume" || fail "task mirror:purge removed $decoy_volume, which is not the mirror volume"

must_succeed mirror:purge
expect_output "no mirror volume"

e2e_finish
