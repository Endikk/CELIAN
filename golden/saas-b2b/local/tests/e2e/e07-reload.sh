#!/usr/bin/env bash
# control: E07
# carries: FR-007; ADR-006, condition 6; contracts/task-cli.md (task reload)
#
# task reload rebuilds the images of the API and the front, loads them and
# applies the manifests again, without touching the database (spec 001,
# T084), on the environment that task up left:
# - with no change of the sources, the objects stay the same: the generation
#   of each Deployment and of the StatefulSet is unchanged, the pods of the
#   database and the cache keep their UID, and the image of each Deployment
#   differs at most by its tag;
# - after a change of the API, then of the front, task reload serves the new
#   version (a marker in the answer of /api/healthz, then in the page), the
#   pod of the database is not restarted (same UID, same restart count), and
#   a note written before is still readable.
# The test changes two tracked files of src/ and puts them back, on exit
# too; a last task reload serves the original sources again.
set -uo pipefail
# shellcheck disable=SC1091 # lib/e2e.sh is checked on its own
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/e2e.sh"

readonly API_SOURCE="$E2E_ROOT/src/Api/Health/HealthEndpoints.cs"
readonly FRONT_SOURCE="$E2E_ROOT/src/front/index.html"
readonly API_ORIGINAL='private const string Ok = "ok";'
readonly API_CHANGED='private const string Ok = "ok-e07";'
readonly FRONT_ORIGINAL='<title>Notes</title>'
readonly FRONT_CHANGED='<title>Notes e07</title>'
readonly SERVE_SECONDS=60

# The test changes two tracked files and puts them back by a trap, which a
# kill -9 skips. It starts only on a clean tracked tree, so that a copy it
# left behind is seen at the next start and never taken for the original
# (tasks.md, gap 156); out of a Git repository, the two files must hold their
# original text.
if tracked_changes="$(git -C "$E2E_ROOT" status --porcelain --untracked-files=no 2>/dev/null)"; then
  if [ -n "$tracked_changes" ]; then
    printf 'E07: the tracked tree of %s is not clean; commit or restore it first, since this test changes two tracked files:\n%s\n' "$E2E_ROOT" "$tracked_changes"
    exit 1
  fi
fi
for original in "$API_SOURCE:$API_ORIGINAL" "$FRONT_SOURCE:$FRONT_ORIGINAL"; do
  if ! grep -qF -- "${original#*:}" "${original%%:*}"; then
    printf 'E07: %s does not hold %s: a previous run left it changed, or it was edited. Restore it first.\n' "${original%%:*}" "${original#*:}"
    exit 1
  fi
done

backup="$(mktemp -d)" || exit 2
cp "$API_SOURCE" "$backup/api.cs" && cp "$FRONT_SOURCE" "$backup/front.html" || exit 2
restore_sources() {
  cp "$backup/api.cs" "$API_SOURCE"
  cp "$backup/front.html" "$FRONT_SOURCE"
  rm -rf "${backup:?}"
}
trap restore_sources EXIT

# replace_in FILE FROM TO: FILE with its one occurrence of FROM changed to
# TO, which fails when FROM is not found.
replace_in() {
  local file="$1" from="$2" to="$3" text
  text="$(cat "$file")" || return 1
  case "$text" in
    *"$from"*) ;;
    *) return 1 ;;
  esac
  # No quotes around the replacement: bash 3.2 would keep them in the text.
  printf '%s\n' "${text/"$from"/$to}" >"$file"
}

ns="$E2E_APP_NAMESPACE"

# pod_uid SELECTOR: the UID of the first pod that SELECTOR matches.
pod_uid() {
  kube_e2e --namespace "$ns" get pods --selector "$1" --output 'jsonpath={.items[0].metadata.uid}'
}

# restarts SELECTOR: the restart counts of the containers of the pods.
restarts() {
  kube_e2e --namespace "$ns" get pods --selector "$1" --output 'jsonpath={.items[*].status.containerStatuses[*].restartCount}'
}

# generations: the generation of each workload, one per line.
generations() {
  kube_e2e --namespace "$ns" get deployments,statefulsets --output 'jsonpath={range .items[*]}{.kind}/{.metadata.name}={.metadata.generation}{"\n"}{end}'
}

# images_with_tag: the image of each workload as written, one per line.
images_with_tag() {
  kube_e2e --namespace "$ns" get deployments,statefulsets \
    --output 'jsonpath={range .items[*]}{.metadata.name}={range .spec.template.spec.containers[*]}{.image} {end}{"\n"}{end}'
}

# images_without_tag: the image of each workload without its tag, one per line.
images_without_tag() {
  kube_e2e --namespace "$ns" get deployments,statefulsets \
    --output 'jsonpath={range .items[*]}{.metadata.name}={range .spec.template.spec.containers[*]}{.image} {end}{"\n"}{end}' |
    sed -e 's/:[A-Za-z0-9._-]*@/@/g' -e 's#\(saas-b2b.invalid/[a-z]*\):[A-Za-z0-9._-]*#\1#g'
}

must_succeed up || e2e_finish

# A note written before the reloads.
http_request POST /api/notes '{"body":"E07 note written before the reloads"}' || {
  fail "POST /api/notes gets no HTTP answer"
  e2e_finish
}
[ "$HTTP_STATUS" = 201 ] || {
  fail "POST /api/notes answers $HTTP_STATUS, 201 expected: $HTTP_BODY"
  e2e_finish
}
note_id="$(json_field id)"

db_selector="app.kubernetes.io/name=postgres"
cache_selector="app.kubernetes.io/name=cache"
db_uid="$(pod_uid "$db_selector")"
db_restarts="$(restarts "$db_selector")"
cache_uid="$(pod_uid "$cache_selector")"
[ -n "$db_uid" ] || {
  fail "no pod of the database found"
  e2e_finish
}

# --- Without a change -------------------------------------------------------------

before_generations="$(generations)"
before_images="$(images_without_tag)"
before_tags="$(images_with_tag)"
must_succeed reload || e2e_finish
# The tag follows the image: with the same sources the same image is built
# and the objects do not change at all; if the engine built another image,
# only the tags may differ (contracts/task-cli.md, task reload).
if [ "$(images_with_tag)" = "$before_tags" ]; then
  [ "$(generations)" = "$before_generations" ] ||
    fail "task reload without a change of the sources changed the objects: generations were
$before_generations
and are now
$(generations)"
else
  printf 'note: the engine built other images from the same sources, the tags changed.\n'
fi
[ "$(images_without_tag)" = "$before_images" ] || fail "task reload without a change changed an image beyond its tag"
[ "$(pod_uid "$db_selector")" = "$db_uid" ] || fail "task reload without a change restarted the pod of the database"
[ "$(pod_uid "$cache_selector")" = "$cache_uid" ] || fail "task reload without a change restarted the pod of the cache"

# check_data: the database was not touched by the reload, and the note is
# still readable.
check_data() {
  [ "$(pod_uid "$db_selector")" = "$db_uid" ] || fail "$1: the pod of the database was replaced"
  [ "$(restarts "$db_selector")" = "$db_restarts" ] || fail "$1: the database restarted"
  if http_request GET "/api/notes/$note_id"; then
    [ "$HTTP_STATUS" = 200 ] || fail "$1: GET /api/notes/$note_id answers $HTTP_STATUS, 200 expected"
  else
    fail "$1: GET /api/notes/$note_id gets no HTTP answer"
  fi
}
check_data "without a change"

# --- After a change of the API ----------------------------------------------------

if replace_in "$API_SOURCE" "$API_ORIGINAL" "$API_CHANGED"; then
  must_succeed reload || e2e_finish
  if wait_http GET /api/healthz 200 "$SERVE_SECONDS"; then
    case "$HTTP_BODY" in
      *ok-e07*) ;;
      *) fail "after a change of the API, /api/healthz still answers the old version: $HTTP_BODY" ;;
    esac
  else
    fail "/api/healthz does not answer 200 within $SERVE_SECONDS s after the reload of the API"
  fi
  check_data "after the change of the API"
else
  fail "could not change $API_SOURCE: $API_ORIGINAL not found"
fi

# --- After a change of the front --------------------------------------------------

if replace_in "$FRONT_SOURCE" "$FRONT_ORIGINAL" "$FRONT_CHANGED"; then
  must_succeed reload || e2e_finish
  if wait_http GET / 200 "$SERVE_SECONDS"; then
    case "$HTTP_BODY" in
      *'Notes e07'*) ;;
      *) fail "after a change of the front, GET / still answers the old page" ;;
    esac
  else
    fail "GET / does not answer 200 within $SERVE_SECONDS s after the reload of the front"
  fi
  check_data "after the change of the front"
else
  fail "could not change $FRONT_SOURCE: $FRONT_ORIGINAL not found"
fi

# --- The original sources again -----------------------------------------------------

cp "$backup/api.cs" "$API_SOURCE" && cp "$backup/front.html" "$FRONT_SOURCE"
must_succeed reload || e2e_finish
if wait_http GET /api/healthz 200 "$SERVE_SECONDS"; then
  case "$HTTP_BODY" in
    *ok-e07*) fail "after the sources were put back, /api/healthz still answers the marker" ;;
  esac
fi
check_data "with the original sources"

e2e_finish
