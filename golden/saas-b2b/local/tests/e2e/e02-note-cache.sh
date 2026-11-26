#!/usr/bin/env bash
# control: E02
# carries: FR-001, FR-009, FR-014; ADR-015, conditions 5 and 17; research RS-11
#
# A note is written to the database, read back, then served by the cache
# (spec 001, T083), on the environment that task up left; and the API
# survives a change of the password of the cache (tasks.md, gap 127):
# 1. POST /api/notes answers 201 and an id; the first GET of that id says
#    servedFrom database, the second servedFrom cache; the list holds it;
# 2. WRONGPASS: cache-auth is replaced by a new password through a pipe and
#    the cache restarted, without restarting the API. The API holds the old
#    password until it reads its mounted file again: /api/readyz must come
#    back to 200 by itself, within the time the kubelet takes to refresh the
#    mounted Secret, and the note is served from the cache again, within that
#    time too (readyz can say 200 on the connection to the old pod);
# 3. task up after the deletion of cache-auth draws a new password, restarts
#    the cache and the API (local/scripts/secrets.sh), and ends with the API
#    ready and the cache serving.
# No password is printed or put in an argument: the new one goes from a
# printf, a builtin, into the pipe of kubectl create.
set -uo pipefail
# shellcheck disable=SC1091 # lib/e2e.sh is checked on its own
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/e2e.sh"

# The kubelet refreshes a mounted Secret on its sync period (one minute by
# default) plus its cache delay: four minutes leave room for both.
readonly RECOVERY_SECONDS=240
readonly READY_SECONDS=120

must_succeed up || e2e_finish

# serve_note ID EXPECTED: GET /api/notes/ID answers 200 with servedFrom
# EXPECTED.
serve_note() {
  if ! http_request GET "/api/notes/$1"; then
    fail "GET /api/notes/$1 gets no HTTP answer"
    return 1
  fi
  if [ "$HTTP_STATUS" != 200 ]; then
    fail "GET /api/notes/$1 answers $HTTP_STATUS, 200 expected: $HTTP_BODY"
    return 1
  fi
  if [ "$(json_field servedFrom)" != "$2" ]; then
    fail "GET /api/notes/$1 says servedFrom \"$(json_field servedFrom)\", $2 expected: $HTTP_BODY"
    return 1
  fi
}

# wait_cache ID SECONDS: GET /api/notes/ID until it answers 200 with servedFrom
# cache, SECONDS at most. After the cache restarts, /api/readyz may answer 200
# on the connection to the old pod, which closes a moment later; the reads then
# come from the database, as the contract wants of a cache that is away
# (contracts/http-api.md), until the API has connected anew (tasks.md, gap 176).
# Each read that finds the database fills the cache again once the client
# connects, so the loop ends on the next one.
wait_cache() {
  local waited=0
  while :; do
    if http_request GET "/api/notes/$1" && [ "$HTTP_STATUS" = 200 ] &&
      [ "$(json_field servedFrom)" = cache ]; then
      return 0
    fi
    [ "$waited" -lt "$2" ] || break
    sleep 2
    waited=$((waited + 2))
  done
  fail "GET /api/notes/$1 is not served from the cache within $2 s after /api/readyz said 200 (last answer $HTTP_STATUS): $HTTP_BODY"
  return 1
}

# --- 1. Database, then cache ---------------------------------------------------

text="E02 note $$-$SECONDS"
if ! http_request POST /api/notes "{\"body\":\"$text\"}"; then
  fail "POST /api/notes gets no HTTP answer"
  e2e_finish
fi
[ "$HTTP_STATUS" = 201 ] || {
  fail "POST /api/notes answers $HTTP_STATUS, 201 expected: $HTTP_BODY"
  e2e_finish
}
id="$(json_field id)"
[ -n "$id" ] || {
  fail "the answer of POST /api/notes holds no id: $HTTP_BODY"
  e2e_finish
}

serve_note "$id" database
serve_note "$id" cache
if http_request GET "/api/notes?limit=50"; then
  case "$HTTP_BODY" in
    *"$id"*) ;;
    *) fail "GET /api/notes does not list the note $id: $HTTP_BODY" ;;
  esac
else
  fail "GET /api/notes gets no HTTP answer"
fi

# --- 2. WRONGPASS: the API holds the old password -------------------------------

if kube_e2e --namespace "$E2E_APP_NAMESPACE" delete secret "$E2E_CACHE_SECRET" --wait=true >/dev/null &&
  printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: %s\ntype: Opaque\nstringData:\n  password: %s\n' \
    "$E2E_CACHE_SECRET" "$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 40)" |
  kube_e2e --namespace "$E2E_APP_NAMESPACE" create -f - >/dev/null &&
  kube_e2e --namespace "$E2E_APP_NAMESPACE" rollout restart deployment/cache >/dev/null &&
  kube_e2e --namespace "$E2E_APP_NAMESPACE" rollout status deployment/cache --timeout=120s >/dev/null; then
  if wait_http GET /api/readyz 200 "$RECOVERY_SECONDS"; then
    case "$HTTP_BODY" in
      *'"cache":"ok"'*) ;;
      *) fail "/api/readyz answers 200 but does not report the cache as ok: $HTTP_BODY" ;;
    esac
    # The note may have left with the old cache: a read fills it again, and
    # the cache must serve it before the end of the recovery time.
    wait_cache "$id" "$RECOVERY_SECONDS"
  else
    fail "/api/readyz does not come back to 200 within $RECOVERY_SECONDS s after the password of the cache changed: the API keeps the old one (tasks.md, gap 127)"
  fi
else
  fail "could not replace cache-auth and restart the cache"
fi

# --- 3. task up after the deletion of cache-auth --------------------------------

if kube_e2e --namespace "$E2E_APP_NAMESPACE" delete secret "$E2E_CACHE_SECRET" --wait=true >/dev/null; then
  must_succeed up || e2e_finish
  if wait_http GET /api/readyz 200 "$READY_SECONDS"; then
    wait_cache "$id" "$READY_SECONDS"
  else
    fail "/api/readyz does not answer 200 within $READY_SECONDS s after task up drew a new password for the cache"
  fi
else
  fail "could not delete cache-auth"
fi

e2e_finish
