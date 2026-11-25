#!/usr/bin/env bash
# control: E03
# carries: FR-002, FR-003; ADR-004, condition 1; ADR-006, condition 3; ADR-011, conditions 1 and 2; R-34
#
# E03, as steps 6 to 8 can check it (tasks.md, gaps 2, 20, 21 and 34):
# - every port that a node of the cluster publishes listens on 127.0.0.1,
#   in the bindings of the engine and in the listening sockets of the
#   machine (ss on Linux, lsof on macOS): nothing on 0.0.0.0, [::] or *;
#   the two host ports of the gateway are among them (T056);
# - the mirror publishes no port, and joins the network kind alone: it has
#   no authentication (R-34);
# - the engine reports the hardening of the mirror: CapDrop ALL, no CapAdd,
#   ReadonlyRootfs, SecurityOpt no-new-privileges, not privileged;
# - the gateway answers on 127.0.0.1 (FR-002). task up applies the Gateway
#   and the HTTPRoutes with local/k8s/lite (T070; tasks.md, gap 36). Once
#   the Gateway is Programmed, GET / and GET /api/healthz on the HTTP port
#   must get an HTTP answer other than 404, the answer of Envoy when no
#   route matches: the HTTPRoutes match. Their Services arrive with step 9,
#   and Gateway API wants a 500 meanwhile (research RS-02);
# - the node pulled the image of the proxy through the mirror: the log of
#   zot shows a GET in 200 of its manifest by digest, with ns=docker.io
#   (tasks.md, gap 20; ADR-011, condition 1). The proxy runs from the first
#   Gateway on: E03 expects a node that has not pulled it yet, as run.sh
#   gives it.
# - the namespace envoy-gateway-system enforces Pod Security (restricted or
#   baseline) and Pod Security refused none of its pods;
# - what a pod of the cluster reaches of the mirror, recorded and not judged
#   (ADR-011, condition 2; R-34; tasks.md, gaps 21 and 34): from a pod of
#   another namespace, on the Postgres image, which carries bash, E03 prints
#   whether the name of the mirror resolves, and the status line of GET
#   /v2/_catalog and of the start of a push, POST /v2/<name>/blobs/uploads/.
#   It fails only when the pod cannot run. The read-only policy of zot is
#   tried at step 10 (tasks.md, gap 29).
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

# task up applies the Gateway with local/k8s/lite (step 8, T070).
if ! kube_e2e -n "$E2E_APP_NAMESPACE" get "gateway/$E2E_GATEWAY" >/dev/null 2>&1; then
  fail "task up applied no Gateway $E2E_GATEWAY in $E2E_APP_NAMESPACE (local/k8s/lite)"
  e2e_finish
fi
if ! kube_e2e -n "$E2E_APP_NAMESPACE" wait --for=condition=Programmed \
  --timeout="${GATEWAY_WAIT_SECONDS}s" "gateway/$E2E_GATEWAY" >/dev/null; then
  fail "the Gateway $E2E_GATEWAY is not Programmed within $GATEWAY_WAIT_SECONDS s"
  kube_e2e -n "$E2E_APP_NAMESPACE" get gateway "$E2E_GATEWAY" --output yaml || :
  e2e_finish
fi

# Pod Security on the namespace of Envoy Gateway: the label is on the live
# namespace (restricted or baseline), and no pod of the controller, of certgen
# or of the proxy was refused for it, the Gateway being Programmed.
readonly CONTROLLER_NAMESPACE="envoy-gateway-system"
pod_security="$(kube_e2e get namespace "$CONTROLLER_NAMESPACE" \
  --output 'jsonpath={.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null)"
case "$pod_security" in
  restricted | baseline) printf 'note: %s enforces Pod Security %s.\n' "$CONTROLLER_NAMESPACE" "$pod_security" ;;
  *) fail "the namespace $CONTROLLER_NAMESPACE has no pod-security.kubernetes.io/enforce of restricted or baseline (found \"$pod_security\")" ;;
esac
refused="$(kube_e2e -n "$CONTROLLER_NAMESPACE" get events --field-selector reason=FailedCreate \
  --output 'jsonpath={range .items[*]}{.message}{"\n"}{end}' 2>/dev/null | grep -F 'violates PodSecurity' || true)"
if [ -n "$refused" ]; then
  fail "Pod Security refused a pod of $CONTROLLER_NAMESPACE: $refused"
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

# What a pod reaches of the mirror, from a namespace of its own. The script
# runs in the pod, $1 being the name of the mirror container; connect sends
# one request ($1 in it) to the mirror ($0 in it), and prints the status line.
readonly PROBE_NAMESPACE="e2e-e03-probe"
# shellcheck disable=SC2016 # expanded by bash in the pod
probe_script='connect="exec 3<>/dev/tcp/\$0/5000 && printf \"%s HTTP/1.0\\r\\nHost: %s\\r\\nContent-Length: 0\\r\\n\\r\\n\" \"\$1\" \"\$0\" >&3 && head -n 1 <&3 | tr -d \"\\r\""
if getent hosts "$1" >/dev/null; then echo "name $1: resolved"; else echo "name $1: not resolved"; fi
for request in "GET /v2/_catalog" "POST /v2/e2e-probe/blobs/uploads/"; do
  line="$(timeout 5 bash -c "$connect" "$1" "$request" 2>/dev/null)" || line="no answer"
  echo "$request: ${line:-no answer}"
done'
trap 'remove_client_namespace "$PROBE_NAMESPACE"' EXIT
if client_namespace "$PROBE_NAMESPACE"; then
  client_pod "$PROBE_NAMESPACE" mirror-probe "set -- $E2E_MIRROR; $probe_script"
  if [ "$STATUS" -eq 0 ]; then
    printf '%s\n' "$OUTPUT" | sed 's/^/note: a pod of the cluster, towards the mirror: /'
  else
    fail "the pod that probes the mirror did not run to its end"
    show_output
  fi
else
  fail "could not create the namespace $PROBE_NAMESPACE of the probe of the mirror"
fi

e2e_finish
