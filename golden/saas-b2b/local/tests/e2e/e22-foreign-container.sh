#!/usr/bin/env bash
# control: E22
# carries: FR-007; ADR-011, condition 11
#
# task down never removes a container that is not the project's, even with
# a name close to the mirror's, or with the label of the project under
# another name; and a container that holds the very name of the mirror
# without the label of the project is left alone by task down and makes
# task up stop, without removing it.
#
# The decoys are created by docker create, never started, on the network
# none, from the zot image that task up already pulled (--pull never): no
# other image, no process, no network. The test removes them at its end.
set -uo pipefail
# shellcheck disable=SC1091 # lib/e2e.sh is checked on its own
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/e2e.sh"

image="$(mirror_image)"
if [ -z "$image" ]; then
  fail "no MIRROR_IMAGE in local/tasks/local.yml"
  e2e_finish
fi
neighbours="$E2E_MIRROR-decoy decoy-$E2E_MIRROR ${E2E_MIRROR}2"
created=""

remove_decoys() {
  local name
  for name in $created; do
    docker container rm "$name" >/dev/null 2>&1 || printf 'E22: could not remove the decoy %s.\n' "$name"
  done
}
trap remove_decoys EXIT

# decoy NAME [LABEL]: creates a stopped container NAME from the zot image.
decoy() {
  local -a label=()
  [ -n "${2:-}" ] && label=(--label "$2")
  if docker container create --pull never --network none --name "$1" ${label[@]+"${label[@]}"} "$image" >/dev/null; then
    created="$created $1"
  else
    fail "could not create the decoy $1"
  fi
}

must_succeed up || e2e_finish

for name in $neighbours; do
  decoy "$name" "$E2E_LABEL"
done
must_succeed down
for name in $neighbours; do
  container_exists "$name" || fail "task down removed the container $name, which is not the mirror of the project"
done
if container_exists "$E2E_MIRROR"; then
  fail "task down left the mirror container $E2E_MIRROR"
fi

# The very name of the mirror, without the label of the project.
decoy "$E2E_MIRROR"
run_task down
container_exists "$E2E_MIRROR" || fail "task down removed $E2E_MIRROR, which has not the label of the project"
expect_output "is not the mirror of this project"

run_task up
if [ "$STATUS" -eq 0 ]; then
  fail "task up succeeded over a container named $E2E_MIRROR that is not the project's"
fi
container_exists "$E2E_MIRROR" || fail "task up removed $E2E_MIRROR, which has not the label of the project"
expect_output "is not the mirror of this project"
labels="$(docker container inspect --format '{{json .Config.Labels}}' "$E2E_MIRROR" 2>/dev/null)"
case "$labels" in
  *invalid.saas-b2b.role*) fail "task up replaced the decoy $E2E_MIRROR with its own container" ;;
esac

e2e_finish
