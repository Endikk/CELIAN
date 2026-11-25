#!/usr/bin/env bash
# control: E03
# carries: FR-003; ADR-004, condition 1; ADR-011, condition 2; R-34
#
# Part of E03 that step 6 can check (tasks.md, gap 2): what the cluster and
# the mirror publish. Step 7 adds the two host ports of the gateway (T056).
# - every port that a node of the cluster publishes listens on 127.0.0.1,
#   in the bindings of the engine and in the listening sockets of the
#   machine (ss on Linux, lsof on macOS): nothing on 0.0.0.0, [::] or *;
# - the mirror publishes no port, and joins the network kind alone: it has
#   no authentication (R-34).
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
    fail "nothing listens on the published port $port"
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

e2e_finish
