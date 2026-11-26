#!/usr/bin/env bash
# control: E20
# carries: FR-016; ADR-011, conditions 5, 9 and 11
#
# The volume of the mirror (spec 001, T125):
# - it is a volume of the engine, mounted where zot keeps its storage, and
#   it sits outside the tree of the project (condition 9): the storage is
#   never a bind mount of a folder of the repo, and the mountpoint of the
#   volume is not under it;
# - task down removes the container and keeps the volume (condition 11);
# - task mirror:purge says that the next task up needs the network before it
#   removes the volume, and the volume is gone (condition 5);
# - after the purge, a task up with the network fills the mirror again, and
#   what it holds is the images of the project and nothing else: every
#   repository of its catalog is one that a container of the cluster runs,
#   and none carries a tag, since the project references its images by
#   digest alone (condition 5: "le stockage ne garde que ce que la version
#   courante du projet référence").
set -uo pipefail
# shellcheck disable=SC1091 # lib/offline.sh is checked on its own
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/offline.sh"

readonly PROBE_NAMESPACE="e2e-e20-probe"
readonly TAGS_NAMESPACE="e2e-e20-tags"
readonly STORAGE_IN_CONTAINER="/var/lib/registry"

# 1. The first start, with the network: the volume exists and sits outside
# the tree.
offline_work || exit 2
trap 'remove_client_namespace "$PROBE_NAMESPACE"; remove_client_namespace "$TAGS_NAMESPACE"; rm -rf "${OFFLINE_WORK:?}"' EXIT
up_within "$OFFLINE_UP_LIMIT_SECONDS" || e2e_finish
if ! volume_exists "$E2E_VOLUME"; then
  fail "no volume $E2E_VOLUME after task up"
  e2e_finish
fi

storage_type="$(docker container inspect \
  --format "{{range .Mounts}}{{if eq .Destination \"$STORAGE_IN_CONTAINER\"}}{{.Type}} {{.Name}}{{end}}{{end}}" "$E2E_MIRROR" 2>/dev/null)"
[ "$storage_type" = "volume $E2E_VOLUME" ] ||
  fail "the storage $STORAGE_IN_CONTAINER of the mirror is \"$storage_type\", \"volume $E2E_VOLUME\" expected: a bind mount could sit in the tree of the project"
bind_sources="$(docker container inspect --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}{{"\n"}}{{end}}{{end}}' "$E2E_MIRROR" 2>/dev/null)"
for bind in $bind_sources; do
  case "$bind" in
    "$E2E_ROOT"/local/mirror/zot/config.json) ;;
    "$E2E_ROOT"/*) fail "the mirror mounts $bind, a folder of the project, besides its configuration" ;;
  esac
done
mountpoint="$(docker volume inspect --format '{{.Mountpoint}}' "$E2E_VOLUME" 2>/dev/null)"
case "$mountpoint" in
  "$E2E_ROOT"/*) fail "the mountpoint $mountpoint of the mirror volume is under the project tree $E2E_ROOT" ;;
esac
printf 'note: the mirror volume %s is mounted on %s, its mountpoint is %s.\n' "$E2E_VOLUME" "$STORAGE_IN_CONTAINER" "${mountpoint:-unknown}"

# 2. task down keeps the volume and removes the container.
must_succeed down || e2e_finish
container_exists "$E2E_MIRROR" && fail "task down left the mirror container"
volume_exists "$E2E_VOLUME" || fail "task down removed the mirror volume"

# 3. task mirror:purge warns, then removes the volume.
must_succeed mirror:purge || e2e_finish
warning_line="$(printf '%s\n' "$OUTPUT" | grep -n -i 'next task up will need the network' | head -n 1 | cut -d: -f1)"
removed_line="$(printf '%s\n' "$OUTPUT" | grep -n -i "volume $E2E_VOLUME removed" | head -n 1 | cut -d: -f1)"
if [ -z "$warning_line" ] || [ -z "$removed_line" ] || [ "$warning_line" -ge "$removed_line" ]; then
  fail "task mirror:purge does not say that the next task up needs the network before it removes the volume"
  show_output
fi
volume_exists "$E2E_VOLUME" && fail "task mirror:purge left the volume $E2E_VOLUME"

# 4. A task up with the network fills the mirror again, with the project's
# images alone.
up_within "$OFFLINE_UP_LIMIT_SECONDS" || e2e_finish
volume_exists "$E2E_VOLUME" || fail "no volume $E2E_VOLUME after the task up that follows the purge"
mirror_probe "$PROBE_NAMESPACE" "GET /v2/_catalog" || e2e_finish
catalog="$(probe_body "GET /v2/_catalog")"
held="$(printf '%s' "$catalog" | tr -d ' ' | sed -n 's/.*"repositories":\[\([^]]*\)\].*/\1/p' | tr ',' '\n' | tr -d '"' | grep . | LC_ALL=C sort -u)"
expected="$(image_repositories)"
if [ -z "$held" ]; then
  fail "the catalog of the mirror is empty after a task up with the network (catalog: $catalog)"
fi
if [ -z "$expected" ]; then
  fail "no image of the registries of local/mirror/registries runs in the cluster: nothing to compare the catalog with"
fi
for repository in $held; do
  case "
$expected
" in
    *"
$repository
"*) ;;
    *) fail "the mirror holds $repository, which no container of the cluster runs: it is not an image of the project" ;;
  esac
done
for repository in $expected; do
  case "
$held
" in
    *"
$repository
"*) ;;
    *) fail "the mirror does not hold $repository, which a container of the cluster runs: the node did not pull it through the mirror" ;;
  esac
done
printf 'note: the mirror holds %s, the images of the project.\n' "$(printf '%s' "$held" | tr '\n' ' ')"

# No tag: the images are referenced by digest. A tag in the storage would be
# a reference by tag, which the mirror does not vouch for (ADR-011, condition 4).
tag_requests=()
for repository in $held; do
  tag_requests+=("GET /v2/$repository/tags/list")
done
mirror_probe "$TAGS_NAMESPACE" "${tag_requests[@]}" || e2e_finish
for repository in $held; do
  tags="$(probe_body "GET /v2/$repository/tags/list" | tr -d ' ')"
  case "$tags" in
    *'"tags":["'*) fail "the mirror holds tags of $repository: $tags; the project references its images by digest alone" ;;
  esac
done

e2e_finish
