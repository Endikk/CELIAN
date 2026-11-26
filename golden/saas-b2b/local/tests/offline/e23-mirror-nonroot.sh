#!/usr/bin/env bash
# control: E23
# carries: FR-016; ADR-011, conditions 1, 2, 6 and 13, complement of 2026-11-26; tasks.md, gaps 29, 92 and 95
#
# The trial of condition 6 of ADR-011 (spec 001, T125), for [SECU]: the mirror
# runs under a UID that is not root, with no capability and no privilege
# gained, and still works. The test starts from a new volume (task down, task
# mirror:purge, task up with the network) and reads back from the engine, not
# from the command line:
# - the container runs under a numeric UID other than 0, drops ALL
#   capabilities, adds none, gains no privilege, has a read-only root
#   filesystem and is not privileged;
# - the mirror writes to its volume under that UID: its catalog lists the
#   images that the node pulled (the on-demand sync wrote them), and its log
#   holds no permission error;
# - the volume that this UID wrote is reused by the next task up (task down,
#   then task up): the mirror starts again on it, serves, and logs no
#   permission error;
# - from a pod, the read stays open (GET /v2/_catalog answers 200) and every
#   write is refused with 401: the start of a push, a push by chunks (PATCH),
#   the mount of a blob from another repository (POST ?mount=), the PUT and
#   the DELETE of a manifest, the DELETE of a blob (gap 95). The anonymous
#   read-only policy decides before any file is touched, so the UID changes
#   none of them: that is what the test shows.
# The result is printed as a block for [SECU]. A failure of the trial is a
# result too: [SECU] then says whether root stays acceptable (condition 6).
set -uo pipefail
# shellcheck disable=SC1091 # lib/offline.sh is checked on its own
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/offline.sh"

readonly PROBE_NAMESPACE="e2e-e23-probe"
readonly SECOND_NAMESPACE="e2e-e23-probe-writes"
readonly THIRD_NAMESPACE="e2e-e23-probe-reuse"
readonly PROXY_REPOSITORY="envoyproxy/envoy"
readonly POSTGRES_REPOSITORY="library/postgres"
offline_work || exit 2
trap 'remove_client_namespace "$PROBE_NAMESPACE"; remove_client_namespace "$SECOND_NAMESPACE"; remove_client_namespace "$THIRD_NAMESPACE"; rm -rf "${OFFLINE_WORK:?}"' EXIT

inspect_mirror() {
  docker container inspect --format "$1" "$E2E_MIRROR" 2>/dev/null
}

# check_mirror_engine: what the engine reports of the container, as failures.
check_mirror_engine() {
  local user cap_drop cap_add security_opt read_only privileged
  user="$(inspect_mirror '{{.Config.User}}')"
  if [[ $user =~ ^([0-9]+)(:[0-9]+)?$ ]] && [ "${BASH_REMATCH[1]}" -gt 0 ]; then
    printf 'result: the mirror runs under the user %s.\n' "$user"
  else
    fail "the mirror runs under the user \"${user:-root, the user of the image}\"; a numeric UID other than 0 is expected (ADR-011, condition 6)"
  fi
  cap_drop="$(inspect_mirror '{{json .HostConfig.CapDrop}}')"
  [ "$cap_drop" = '["ALL"]' ] || fail "the mirror drops the capabilities $cap_drop, [\"ALL\"] expected"
  cap_add="$(inspect_mirror '{{json .HostConfig.CapAdd}}')"
  case "$cap_add" in
    null | "[]") ;;
    *) fail "the mirror adds the capabilities $cap_add" ;;
  esac
  security_opt="$(inspect_mirror '{{json .HostConfig.SecurityOpt}}')"
  [ "$security_opt" = '["no-new-privileges=true"]' ] || fail "the mirror has SecurityOpt $security_opt, [\"no-new-privileges=true\"] expected"
  read_only="$(inspect_mirror '{{.HostConfig.ReadonlyRootfs}}')"
  [ "$read_only" = true ] || fail "the mirror has a writable root filesystem (ReadonlyRootfs=$read_only)"
  privileged="$(inspect_mirror '{{.HostConfig.Privileged}}')"
  [ "$privileged" = false ] || fail "the mirror runs privileged (Privileged=$privileged)"
  printf 'result: CapDrop %s, CapAdd %s, SecurityOpt %s, ReadonlyRootfs %s, Privileged %s.\n' \
    "$cap_drop" "$cap_add" "$security_opt" "$read_only" "$privileged"
}

# check_mirror_writes NAMESPACE: the mirror wrote what the node pulled, and
# its log holds no permission error.
check_mirror_writes() {
  local catalog repository errors
  mirror_probe "$1" "GET /v2/_catalog" || return 1
  catalog="$(probe_body "GET /v2/_catalog")"
  for repository in "$PROXY_REPOSITORY" "$POSTGRES_REPOSITORY"; do
    case "$catalog" in
      *"\"$repository\""*) printf 'result: the mirror holds %s, written to its volume.\n' "$repository" ;;
      *) fail "the catalog of the mirror does not list $repository: the mirror did not write what the node pulled (catalog: $catalog)" ;;
    esac
  done
  errors="$(docker logs "$E2E_MIRROR" 2>&1 | grep -i -E 'permission denied|read-only file system|operation not permitted' | head -n 3)"
  [ -z "$errors" ] || fail "the log of the mirror holds permission errors: $errors"
  [ "$(inspect_mirror '{{.State.Running}}')" = true ] || fail "the mirror is not running"
}

# 1. A new volume, then a task up with the network: the UID writes it.
must_succeed down || e2e_finish
must_succeed mirror:purge || e2e_finish
up_within "$OFFLINE_UP_LIMIT_SECONDS" || e2e_finish
container_exists "$E2E_MIRROR" || {
  fail "no mirror container after task up"
  e2e_finish
}
check_mirror_engine
check_mirror_writes "$PROBE_NAMESPACE" || e2e_finish

# 2. Reads open, every write refused.
readonly BLOB_UPLOAD="POST /v2/e2e-probe/blobs/uploads/"
readonly BLOB_MOUNT="POST /v2/e2e-probe/blobs/uploads/?mount=$OFFLINE_EMPTY_BLOB&from=$POSTGRES_REPOSITORY"
readonly BLOB_CHUNK="PATCH /v2/e2e-probe/blobs/uploads/00000000-0000-0000-0000-000000000000"
readonly MANIFEST_PUT="PUT /v2/e2e-probe/manifests/e2e-probe"
readonly MANIFEST_DELETE="DELETE /v2/e2e-probe/manifests/e2e-probe"
readonly BLOB_DELETE="DELETE /v2/$POSTGRES_REPOSITORY/blobs/$OFFLINE_EMPTY_BLOB"
mirror_probe "$SECOND_NAMESPACE" "GET /v2/_catalog" "$BLOB_UPLOAD" "$BLOB_MOUNT" "$BLOB_CHUNK" "$MANIFEST_PUT" "$MANIFEST_DELETE" "$BLOB_DELETE" || e2e_finish
code="$(probe_code "GET /v2/_catalog")"
[ "$code" = 200 ] || fail "a pod of the cluster gets \"${code:-no answer}\" for GET /v2/_catalog; 200 expected, the mirror stays readable"
for request in "$BLOB_UPLOAD" "$BLOB_MOUNT" "$BLOB_CHUNK" "$MANIFEST_PUT" "$MANIFEST_DELETE" "$BLOB_DELETE"; do
  code="$(probe_code "$request")"
  case "$code" in
    401) printf 'result: the mirror refuses %s from a pod with %s.\n' "${request%%\?*}" "$code" ;;
    *) fail "a pod of the cluster gets \"${code:-no answer}\" for $request; 401 expected: a write is not refused (R-34)" ;;
  esac
done

# 3. The volume written by that UID is reused by the next task up.
must_succeed down || e2e_finish
up_within "$OFFLINE_UP_LIMIT_SECONDS" || e2e_finish
check_mirror_engine
check_mirror_writes "$THIRD_NAMESPACE" || e2e_finish
printf 'result: the volume written by that user is reused by the next task up.\n'

e2e_finish
