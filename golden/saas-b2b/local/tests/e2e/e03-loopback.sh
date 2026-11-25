#!/usr/bin/env bash
# control: E03
# carries: FR-002, FR-003; ADR-004, condition 1; ADR-006, condition 3; ADR-011, conditions 1 and 2; R-34
#
# Part of E03 that steps 6 and 7 can check (tasks.md, gaps 2, 20 and 21):
# - every port that a node of the cluster publishes listens on 127.0.0.1,
#   in the bindings of the engine and in the listening sockets of the
#   machine (ss on Linux, lsof on macOS): nothing on 0.0.0.0, [::] or *;
#   the two host ports of the gateway are among them (T056);
# - the mirror publishes no port, and joins the network kind alone: it has
#   no authentication (R-34);
# - the engine reports the hardening of the mirror: CapDrop ALL, no CapAdd,
#   ReadonlyRootfs, SecurityOpt no-new-privileges, not privileged;
# - the gateway answers on 127.0.0.1 (FR-002). Until step 8 applies the
#   application layer in task up (T070), E03 applies the common overlay
#   k8s/overlays/local itself, then removes it. Once the Gateway is
#   Programmed, GET / and GET /api/healthz on the HTTP port must get an
#   HTTP answer other than 404, the answer of Envoy when no route matches:
#   the HTTPRoutes match. Their Services arrive with step 9, and Gateway API
#   wants a 500 meanwhile (research RS-02);
# - the node pulled the image of the proxy through the mirror: the log of
#   zot shows a GET in 200 of its manifest by digest, with ns=docker.io
#   (tasks.md, gap 20; ADR-011, condition 1). The proxy runs from the first
#   Gateway on: E03 expects a node that has not pulled it yet, as run.sh
#   gives it.
# What a pod reaches of the mirror needs an image with a shell: it waits for
# the Postgres image of step 8 (tasks.md, gaps 21 and 30).
set -uo pipefail
# shellcheck disable=SC1091 # lib/e2e.sh is checked on its own
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/e2e.sh"

must_succeed up || e2e_finish

nodes="$(docker container ls --filter "$E2E_NODE_FILTER" --format '{{.Names}}')"
if [ -z "$nodes" ]; then
  fail "no running node of the cluster $E2E_CLUSTER"
  e2e_finish
fi

host_ports=""
for node in $nodes; do
  bindings="$(docker container inspect \
    --format '{{range $port, $list := .HostConfig.PortBindings}}{{range $list}}{{$port}}={{.HostIp}}:{{.HostPort}} {{end}}{{end}}' "$node")"
  if [ -z "$bindings" ]; then
    fail "the node $node publishes no port; kind publishes the API server"
  fi
  for binding in $bindings; do
    address="${binding#*=}"
    case "$address" in
      127.0.0.1:[0-9]*) host_ports="$host_ports ${address#127.0.0.1:}" ;;
      *) fail "the node $node publishes $binding, not on 127.0.0.1" ;;
    esac
  done
done
for port in "$E2E_GATEWAY_HTTP_PORT" "$E2E_GATEWAY_HTTPS_PORT"; do
  case "$host_ports " in
    *" $port "*) ;;
    *) fail "no node publishes the host port $port of the gateway on 127.0.0.1" ;;
  esac
done

# The listening sockets of each published port.
listeners_of() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltnH "sport = :$1" | awk '{ print $4 }'
  elif command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$1" -sTCP:LISTEN -Fn | sed -n 's/^n//p'
  else
    printf 'none\n'
  fi
}

for port in $host_ports; do
  listeners="$(listeners_of "$port")"
  if [ "$listeners" = none ]; then
    fail "neither ss nor lsof is on PATH: the listening sockets cannot be read"
    break
  fi
  if [ -z "$listeners" ]; then
    # The engine can forward a port without a listening process; the
    # bindings above stay the rule.
    printf 'note: no listening socket found for the published port %s.\n' "$port"
  fi
  for listener in $listeners; do
    case "$listener" in
      127.0.0.1:"$port") ;;
      *) fail "port $port listens on $listener, not on 127.0.0.1 alone" ;;
    esac
  done
done

if ! container_exists "$E2E_MIRROR"; then
  fail "no mirror container $E2E_MIRROR after task up"
  e2e_finish
fi
published="$(docker container inspect \
  --format '{{range $port, $list := .HostConfig.PortBindings}}{{$port}} {{end}}{{range $port, $list := .NetworkSettings.Ports}}{{if $list}}{{$port}} {{end}}{{end}}{{if .HostConfig.PublishAllPorts}}all{{end}}' "$E2E_MIRROR")"
if [ -n "$published" ]; then
  fail "the mirror publishes ports: $published"
fi
networks="$(docker container inspect --format '{{range $name, $settings := .NetworkSettings.Networks}}{{$name}} {{end}}' "$E2E_MIRROR")"
if [ "$networks" != "kind " ]; then
  fail "the mirror joins the networks \"$networks\"; kind alone is expected"
fi

# The hardening, read back from the engine and not from the command line: no
# capability, no extra one, no privilege gained, a read-only root
# filesystem, no privileged mode (ADR-011, condition 7; S13 checks the
# command).
inspect_mirror() {
  docker container inspect --format "$1" "$E2E_MIRROR" 2>/dev/null
}
cap_drop="$(inspect_mirror '{{json .HostConfig.CapDrop}}')"
[ "$cap_drop" = '["ALL"]' ] || fail "the mirror drops the capabilities $cap_drop, [\"ALL\"] expected"
cap_add="$(inspect_mirror '{{json .HostConfig.CapAdd}}')"
case "$cap_add" in
  null | "[]") ;;
  *) fail "the mirror adds the capabilities $cap_add" ;;
esac
read_only="$(inspect_mirror '{{.HostConfig.ReadonlyRootfs}}')"
[ "$read_only" = true ] || fail "the mirror has a writable root filesystem (ReadonlyRootfs=$read_only)"
security_opt="$(inspect_mirror '{{json .HostConfig.SecurityOpt}}')"
[ "$security_opt" = '["no-new-privileges=true"]' ] || fail "the mirror has SecurityOpt $security_opt, [\"no-new-privileges=true\"] expected"
privileged="$(inspect_mirror '{{.HostConfig.Privileged}}')"
[ "$privileged" = false ] || fail "the mirror runs privileged (Privileged=$privileged)"

# The gateway, end to end, on the HTTP port. The Gateway waits for the proxy,
# whose image the node pulls through the mirror, from Docker Hub on a new
# mirror volume.
readonly GATEWAY_WAIT_SECONDS=300
readonly ANSWER_SECONDS=60
readonly ANSWER_PAUSE_SECONDS=2
readonly READ_SECONDS=5
readonly PROXY_REPOSITORY="envoyproxy/envoy"
overlay="$E2E_ROOT/k8s/overlays/local"

applied=no
remove_overlay() {
  if [ "$applied" = yes ]; then
    kube_e2e delete -k "$overlay" --ignore-not-found --wait=false >/dev/null 2>&1 ||
      printf 'E03: could not delete the objects of k8s/overlays/local.\n'
  fi
}
trap remove_overlay EXIT

if kube_e2e apply -k "$overlay" >/dev/null; then
  applied=yes
else
  fail "kubectl apply -k k8s/overlays/local failed"
  e2e_finish
fi
if ! kube_e2e -n "$E2E_APP_NAMESPACE" wait --for=condition=Programmed \
  --timeout="${GATEWAY_WAIT_SECONDS}s" "gateway/$E2E_GATEWAY" >/dev/null; then
  fail "the Gateway $E2E_GATEWAY is not Programmed within $GATEWAY_WAIT_SECONDS s"
  kube_e2e -n "$E2E_APP_NAMESPACE" get gateway "$E2E_GATEWAY" --output yaml || :
  e2e_finish
fi

# http_status PORT PATH: the status code that GET PATH gets on
# 127.0.0.1:PORT, read by bash itself through /dev/tcp; fails without an
# HTTP answer.
http_status() {
  local line
  line="$(
    exec 3<>"/dev/tcp/127.0.0.1/$1" || exit 1
    printf 'GET %s HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n' "$2" >&3
    IFS= read -r -t "$READ_SECONDS" first <&3 || exit 1
    printf '%s' "$first"
  )" 2>/dev/null || return 1
  [[ $line =~ ^HTTP/1\.[01]\ ([0-9][0-9][0-9]) ]] || return 1
  printf '%s' "${BASH_REMATCH[1]}"
}

for path in / /api/healthz; do
  waited=0
  while :; do
    code="$(http_status "$E2E_GATEWAY_HTTP_PORT" "$path")" || code=""
    case "$code" in
      "" | 404) ;;
      *) break ;;
    esac
    [ "$waited" -lt "$ANSWER_SECONDS" ] || break
    sleep "$ANSWER_PAUSE_SECONDS"
    waited=$((waited + ANSWER_PAUSE_SECONDS))
  done
  case "$code" in
    "") fail "no HTTP answer on 127.0.0.1:$E2E_GATEWAY_HTTP_PORT$path within $ANSWER_SECONDS s" ;;
    404) fail "127.0.0.1:$E2E_GATEWAY_HTTP_PORT$path answers 404: no HTTPRoute matches it" ;;
    *) printf 'note: 127.0.0.1:%s%s answers %s through the gateway.\n' "$E2E_GATEWAY_HTTP_PORT" "$path" "$code" ;;
  esac
done

# The log of zot: one JSON line per request, with method, path and
# statusCode (zot v2.1.23, pkg/api/session.go, lines 128 to 136).
pulls="$(docker logs "$E2E_MIRROR" 2>&1 | grep -F '"method":"GET"' |
  grep -F "\"path\":\"/v2/$PROXY_REPOSITORY/manifests/sha256:" | grep -F 'ns=docker.io' |
  grep -F '"statusCode":200' || true)"
if [ -z "$pulls" ]; then
  fail "the log of the mirror shows no GET in 200 of a manifest of $PROXY_REPOSITORY with ns=docker.io: the node did not pull the proxy through the mirror"
fi

e2e_finish
