#!/usr/bin/env bash
# control: E08
# carries: FR-007, FR-016; ADR-011, conditions 5 and 11; contracts/task-cli.md
#
# E08, steps 6 and 9 (tasks.md, gaps 2, 12 and 93): task app:down, task down
# and task mirror:purge.
# - task app:down keeps the cluster, removes the mirror container, the
#   namespace of the application with the PVC and the Secrets of the database
#   (and the volume behind the PVC), and says how much memory the cluster
#   keeps; the next task up reuses the cluster, draws new Secrets, and the
#   Gateway is Programmed again, the Role of its controller having gone with
#   the namespace (gap 93);
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

# --- task app:down ----------------------------------------------------------------

readonly PV_WAIT_SECONDS=60
password_before="$(secret_value db-auth password | sha256_stdin)"
must_succeed app:down
cluster_exists || fail "task app:down removed the cluster $E2E_CLUSTER, which it must keep"
container_exists "$E2E_MIRROR" && fail "task app:down left the mirror container $E2E_MIRROR"
volume_exists "$E2E_VOLUME" || fail "task app:down removed the mirror volume $E2E_VOLUME"
if kube_e2e get namespace "$E2E_APP_NAMESPACE" >/dev/null 2>&1; then
  fail "task app:down left the namespace $E2E_APP_NAMESPACE"
fi
# The volume behind the PVC of the database goes with the namespace.
waited=0
while :; do
  claims="$(kube_e2e get pv --output 'jsonpath={range .items[*]}{.spec.claimRef.namespace}{"\n"}{end}' 2>/dev/null | grep -cx "$E2E_APP_NAMESPACE")"
  [ "${claims:-0}" -eq 0 ] && break
  [ "$waited" -lt "$PV_WAIT_SECONDS" ] || {
    fail "a volume still belongs to a claim of $E2E_APP_NAMESPACE $PV_WAIT_SECONDS s after task app:down"
    break
  }
  sleep 2
  waited=$((waited + 2))
done
# The memory that the cluster keeps: a figure and a unit.
memory_line="$(printf '%s\n' "$OUTPUT" | grep -i 'memory' || true)"
if ! [[ $memory_line =~ [0-9.]+\ ?[KMG]i?B ]]; then
  fail "task app:down does not say how much memory the cluster keeps: $memory_line"
  show_output
fi

must_succeed up
if [ "$(secret_value db-auth password | sha256_stdin)" = "$password_before" ]; then
  fail "task up after task app:down kept the old password of db-auth instead of drawing a new one"
fi
programmed="$(kube_e2e --namespace "$E2E_APP_NAMESPACE" get gateway "$E2E_GATEWAY" --output 'jsonpath={.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null)"
[ "$programmed" = True ] || fail "the Gateway $E2E_GATEWAY is not Programmed after task app:down then task up (Programmed=$programmed; tasks.md, gap 93)"
container_exists "$E2E_MIRROR" || fail "task up after task app:down did not start the mirror container again"

# --- task down --------------------------------------------------------------------

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
