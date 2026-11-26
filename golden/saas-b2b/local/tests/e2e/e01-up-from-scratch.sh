#!/usr/bin/env bash
# control: E01
# carries: FR-001, FR-002, FR-009, FR-014; ADR-006; ADR-012, condition 6; contracts/task-cli.md
#
# task up on a machine with no cluster reaches "ready" without any other
# step (spec 001, T083). The test removes the cluster first with task down,
# which keeps the mirror volume, then runs task up once and checks, with no
# wait of its own, what a user would try next:
# - the output gives the address of the front and the one of the API, as
#   http://localhost:<port>/ and http://localhost:<port>/api/, one per line
#   (tasks.md, gap 120: the HTTPRoutes name localhost, since Gateway API
#   refuses an IP in hostnames);
# - an authenticated SELECT 1, as the user of db-auth, through the Service
#   of the database, answers 1;
# - GET /api/healthz and GET /api/readyz answer 200 through the gateway, and
#   GET / answers the page of the front;
# - a request under another Host (127.0.0.1, or a foreign name) gets 404:
#   the HTTPRoutes name their hostnames (tasks.md, gap 45).
set -uo pipefail
# shellcheck disable=SC1091 # lib/e2e.sh is checked on its own
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/e2e.sh"

must_succeed down || e2e_finish
cluster_exists && fail "task down left the cluster $E2E_CLUSTER: the test needs a machine without one"

must_succeed up || e2e_finish

base="http://$E2E_HOST:$E2E_GATEWAY_HTTP_PORT"
for line in "Front: $base/" "API: $base/api/"; do
  if ! printf '%s\n' "$OUTPUT" | grep -qxF "$line"; then
    fail "the output of task up has no line \"$line\""
    show_output
  fi
done

one="$(db_query db-auth app "SELECT 1")" || one=""
[ "$one" = 1 ] || fail "an authenticated SELECT 1 through the Service postgres answers \"$one\", 1 expected"

if http_request GET /api/healthz; then
  [ "$HTTP_STATUS" = 200 ] || fail "GET /api/healthz through the gateway answers $HTTP_STATUS, 200 expected"
  case "$HTTP_BODY" in
    *'"status":"ok"'*) ;;
    *) fail "GET /api/healthz answers a body without status ok: $HTTP_BODY" ;;
  esac
else
  fail "GET /api/healthz gets no HTTP answer through the gateway at $base"
fi

if http_request GET /api/readyz; then
  [ "$HTTP_STATUS" = 200 ] || fail "GET /api/readyz answers $HTTP_STATUS, 200 expected: $HTTP_BODY"
  case "$HTTP_BODY" in
    *'"database":"ok"'*'"cache":"ok"'* | *'"cache":"ok"'*'"database":"ok"'*) ;;
    *) fail "GET /api/readyz does not report the database and the cache as ok: $HTTP_BODY" ;;
  esac
else
  fail "GET /api/readyz gets no HTTP answer through the gateway"
fi

if http_request GET /; then
  [ "$HTTP_STATUS" = 200 ] || fail "GET / answers $HTTP_STATUS, 200 expected"
  case "$HTTP_BODY" in
    *'<div id="root">'*) ;;
    *) fail "GET / does not answer the page of the front (no div root)" ;;
  esac
else
  fail "GET / gets no HTTP answer through the gateway"
fi

# The gateway answers the host that the HTTPRoutes name, and no other: a page
# of another site that points its name at 127.0.0.1 (DNS rebinding) gets no
# route (tasks.md, gap 45).
for foreign in 127.0.0.1 attacker.example; do
  # shellcheck disable=SC2034 # read by http_request of lib/e2e.sh
  E2E_REQUEST_HOST="$foreign"
  for path in / /api/healthz; do
    if http_request GET "$path"; then
      [ "$HTTP_STATUS" = 404 ] || fail "GET $path with the Host $foreign answers $HTTP_STATUS, 404 expected: the HTTPRoutes must name their hostnames"
    else
      fail "GET $path with the Host $foreign gets no HTTP answer"
    fi
  done
done
unset E2E_REQUEST_HOST

# A browser on http://localhost:<port>/ sends the port in Host. Envoy counts
# the port when it picks the virtual host (tasks.md, gap 133): localhost:<port>
# must get the application, a foreign name with the same port must not.
port="$E2E_GATEWAY_HTTP_PORT"
for path in / /api/healthz; do
  E2E_REQUEST_HOST="$E2E_HOST:$port"
  if http_request GET "$path"; then
    [ "$HTTP_STATUS" = 200 ] || fail "GET $path with the Host $E2E_REQUEST_HOST, as a browser sends it, answers $HTTP_STATUS, 200 expected"
  else
    fail "GET $path with the Host $E2E_REQUEST_HOST gets no HTTP answer"
  fi
  for foreign in "attacker.example:$port" "127.0.0.1:$port"; do
    E2E_REQUEST_HOST="$foreign"
    if http_request GET "$path"; then
      [ "$HTTP_STATUS" = 404 ] || fail "GET $path with the Host $foreign answers $HTTP_STATUS, 404 expected"
    else
      fail "GET $path with the Host $foreign gets no HTTP answer"
    fi
  done
done
unset E2E_REQUEST_HOST

e2e_finish
