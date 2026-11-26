#!/usr/bin/env bash
# control: E03
# carries: FR-002, FR-003, FR-004; ADR-004, condition 1; ADR-006, condition 3; ADR-011, conditions 1 and 2; R-34; research RS-10
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
# - the HTTPS listener serves the certificate of the Secret gateway-tls:
#   the SHA-256 fingerprint of the certificate that openssl s_client reads
#   on 127.0.0.1 equals that of tls.crt, and x509 -checkend 0 finds it
#   unexpired (research RS-10; tasks.md, gap 80). No -k, no file;
# - the namespace envoy-gateway-system enforces Pod Security (restricted or
#   baseline) and Pod Security refused none of its pods;
# - what a pod of the cluster reaches of the mirror (ADR-011, condition 2;
#   R-34; tasks.md, gaps 21, 29, 34, 98 and 106): from a pod of another
#   namespace, on the Postgres image, which carries bash, E03 prints whether
#   the name of the mirror resolves and the status line of each request, and
#   judges them. GET /v2/_catalog answers 200. The start of a push, POST
#   /v2/<name>/blobs/uploads/, the PUT of a manifest and the DELETE of one are
#   refused with 401, the status measured: the anonymous policy of zot grants read alone
#   (ADR-011, complement of 2026-11-26). A write that got through fails the
#   test, as does a pod that cannot run;
# - the proxy runs the image that local/platform/envoy-proxy.yaml pins by
#   digest: the EnvoyProxy of the cluster carries the field
#   envoyDeployment.container.image, and the pod of the proxy runs that
#   reference (ADR-005, complement of 2026-11-26);
# - the node pulled the images of the proxy and of Postgres through the
#   mirror (tasks.md, gap 20; ADR-011, condition 1): the catalog of zot,
#   read by the same pod, lists envoyproxy/envoy and library/postgres. The
#   log of zot would not tell since step 8: each task up starts a new mirror
#   container, and the proxy runs from the first task up on.
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
readonly POSTGRES_REPOSITORY="library/postgres"

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

# The HTTPS listener (T074; research RS-10; tasks.md, gap 80). The certificate
# that 127.0.0.1:HTTPS_PORT serves is the one of the Secret gateway-tls, and it
# has not expired. openssl s_client reads the certificate that the listener
# presents, with the name localhost as SNI; no -k, no trust store, no file:
# the certificate goes by pipes, and only public values are compared, the
# SHA-256 fingerprint of the served certificate and that of tls.crt in the
# Secret. The SAN is not checked apart: it is the certificate of the Secret
# that is served, and E04 checks that it is the one task up made.
# served_certificate PORT: the PEM certificate that the listener presents,
# empty when it presents none. s_client is stopped after READ_SECONDS by a
# watchdog whose output goes nowhere, so that the pipe closes with s_client.
served_certificate() {
  {
    openssl s_client -connect "127.0.0.1:$1" -servername localhost </dev/null 2>/dev/null &
    local client=$!
    ( sleep "$READ_SECONDS" && kill "$client" ) >/dev/null 2>&1 &
    local watchdog=$!
    wait "$client" 2>/dev/null
    kill "$watchdog" 2>/dev/null
  } | openssl x509 2>/dev/null
}

served=""
waited=0
while :; do
  served="$(served_certificate "$E2E_GATEWAY_HTTPS_PORT")"
  [ -n "$served" ] && break
  [ "$waited" -lt "$ANSWER_SECONDS" ] || break
  sleep "$ANSWER_PAUSE_SECONDS"
  waited=$((waited + ANSWER_PAUSE_SECONDS))
done
if [ -z "$served" ]; then
  fail "127.0.0.1:$E2E_GATEWAY_HTTPS_PORT presents no certificate within $ANSWER_SECONDS s: the Gateway has no HTTPS listener"
else
  served_sum="$(printf '%s\n' "$served" | cert_fingerprint)"
  secret_sum="$(secret_value "$E2E_TLS_SECRET" tls.crt 2>/dev/null | cert_fingerprint)"
  if [ -z "$secret_sum" ]; then
    fail "the Secret $E2E_TLS_SECRET has no readable certificate tls.crt"
  elif [ "$served_sum" != "$secret_sum" ]; then
    fail "the certificate served on 127.0.0.1:$E2E_GATEWAY_HTTPS_PORT (SHA-256 ${served_sum:-unreadable}) is not the one of the Secret $E2E_TLS_SECRET ($secret_sum)"
  else
    printf 'note: 127.0.0.1:%s serves the certificate of %s, SHA-256 %s.\n' "$E2E_GATEWAY_HTTPS_PORT" "$E2E_TLS_SECRET" "$served_sum"
  fi
  if printf '%s\n' "$served" | openssl x509 -noout -checkend 0 >/dev/null 2>&1; then
    printf 'note: the certificate served on 127.0.0.1:%s has not expired.\n' "$E2E_GATEWAY_HTTPS_PORT"
  else
    fail "the certificate served on 127.0.0.1:$E2E_GATEWAY_HTTPS_PORT has expired: delete the Secret $E2E_TLS_SECRET and run task up"
  fi
fi

# What a pod reaches of the mirror, from a namespace of its own. The script
# runs in the pod, $1 being the name of the mirror container; connect sends
# one request ($1 in it) to the mirror ($0 in it), and prints the answer
# without its carriage returns: the status line first, the body last.
# A refusal can close the connection while the body of a PUT still arrives:
# the client then sees a reset and no answer (it happened once in the CI,
# on the PUT of a manifest). Each request is asked up to three times.
readonly PROBE_NAMESPACE="e2e-e03-probe"
# shellcheck disable=SC2016 # expanded by bash in the pod
probe_script='connect="exec 3<>/dev/tcp/\$0/5000 && printf \"%s HTTP/1.0\\r\\nHost: %s\\r\\nContent-Type: application/vnd.oci.image.manifest.v1+json\\r\\nContent-Length: %s\\r\\n\\r\\n%s\" \"\$1\" \"\$0\" \"\${#2}\" \"\$2\" >&3 && tr -d \"\\r\" <&3"
manifest="{\"schemaVersion\":2,\"mediaType\":\"application/vnd.oci.image.manifest.v1+json\",\"config\":{\"mediaType\":\"application/vnd.oci.empty.v1+json\",\"digest\":\"sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a\",\"size\":2},\"layers\":[]}"
if getent hosts "$1" >/dev/null; then echo "name $1: resolved"; else echo "name $1: not resolved"; fi
for request in "GET /v2/_catalog" "POST /v2/e2e-probe/blobs/uploads/" "PUT /v2/e2e-probe/manifests/e2e-probe" "DELETE /v2/e2e-probe/manifests/e2e-probe"; do
  body=""
  case "$request" in PUT*) body="$manifest" ;; esac
  answer=""
  for try in 1 2 3; do
    answer="$(timeout 5 bash -c "$connect" "$1" "$request" "$body" 2>/dev/null || true)"
    [ -n "$answer" ] && break
  done
  status="$(printf "%s\n" "$answer" | head -n 1)"
  echo "$request: ${status:-no answer}"
  case "$request" in
    GET*) echo "catalog: $(printf "%s\n" "$answer" | tail -n 1)" ;;
  esac
done'
trap 'remove_client_namespace "$PROBE_NAMESPACE"' EXIT
probe=""
if client_namespace "$PROBE_NAMESPACE"; then
  client_pod "$PROBE_NAMESPACE" mirror-probe "set -- $E2E_MIRROR; $probe_script"
  if [ "$STATUS" -eq 0 ]; then
    probe="$OUTPUT"
    printf '%s\n' "$probe" | grep -v '^catalog: ' | sed 's/^/note: a pod of the cluster, towards the mirror: /'
  else
    fail "the pod that probes the mirror did not run to its end"
    show_output
  fi
else
  fail "could not create the namespace $PROBE_NAMESPACE of the probe of the mirror"
fi

# The mirror is read-only for a pod (ADR-011, complement of 2026-11-26;
# tasks.md, gaps 29, 98 and 106): the anonymous policy of zot grants read and
# nothing else, so the catalog answers 200 and each write, the start of a
# push, the PUT of a manifest and the DELETE of one, is refused with 401, the
# status measured on kind (tasks.md, gap 113). A write that got through could
# fill the volume of the mirror and delete what it holds.
# probe_code REQUEST: the status code that the pod got for REQUEST, empty
# when it got no answer.
probe_code() {
  local line
  line="$(printf '%s\n' "$probe" | grep -F -- "$1: " | head -n 1)"
  [[ $line =~ :\ HTTP/1\.[01]\ ([0-9][0-9][0-9]) ]] || return 0
  printf '%s' "${BASH_REMATCH[1]}"
}
code="$(probe_code "GET /v2/_catalog")"
[ "$code" = 200 ] || fail "a pod of the cluster gets \"${code:-no answer}\" for GET /v2/_catalog; 200 expected, the mirror stays readable"
for request in "POST /v2/e2e-probe/blobs/uploads/" "PUT /v2/e2e-probe/manifests/e2e-probe" "DELETE /v2/e2e-probe/manifests/e2e-probe"; do
  code="$(probe_code "$request")"
  case "$code" in
    401) printf 'note: the mirror refuses %s from a pod with %s.\n' "$request" "$code" ;;
    *) fail "a pod of the cluster gets \"${code:-no answer}\" for $request; 401 expected: the mirror is writable without authentication (R-34)" ;;
  esac
done

# The proxy runs the image that the EnvoyProxy pins, by digest (ADR-005,
# complement of 2026-11-26): the EnvoyProxy of the cluster carries the field,
# and the pod of the proxy runs exactly that reference.
readonly PROXY_IMAGE_FIELD='{.spec.provider.kubernetes.envoyDeployment.container.image}'
readonly ENVOY_PROXY_NAME="saas-b2b"
readonly PROXY_POD_SELECTOR="gateway.envoyproxy.io/owning-gateway-name=$E2E_GATEWAY"
expected_proxy="$(proxy_image)"
if ! [[ $expected_proxy =~ ^docker\.io/envoyproxy/envoy:[A-Za-z0-9._-]+@sha256:[a-f0-9]{64}$ ]]; then
  fail "local/platform/envoy-proxy.yaml pins no proxy image by digest under docker.io/envoyproxy/envoy (found \"$expected_proxy\")"
else
  applied="$(kube_e2e -n "$CONTROLLER_NAMESPACE" get envoyproxy "$ENVOY_PROXY_NAME" --output "jsonpath=$PROXY_IMAGE_FIELD" 2>/dev/null)"
  [ "$applied" = "$expected_proxy" ] || fail "the EnvoyProxy of the cluster carries the image \"$applied\", \"$expected_proxy\" expected"
  running="$(kube_e2e -n "$CONTROLLER_NAMESPACE" get pods --selector "$PROXY_POD_SELECTOR" \
    --output 'jsonpath={range .items[*].spec.containers[*]}{.name}={.image}{"\n"}{end}' 2>/dev/null | sed -n 's/^envoy=//p')"
  if [ -z "$running" ]; then
    fail "no pod of the proxy found with the selector $PROXY_POD_SELECTOR in $CONTROLLER_NAMESPACE"
  elif [ "$running" != "$expected_proxy" ]; then
    fail "the pod of the proxy runs \"$running\", \"$expected_proxy\" expected"
  else
    printf 'note: the proxy runs %s, the image that local/platform/envoy-proxy.yaml pins.\n' "$running"
  fi
fi

# The node pulled the proxy and Postgres through the mirror (tasks.md, gap
# 20; ADR-011, condition 1): zot syncs on demand, and its catalog lists the
# repositories it holds, which only a pull through it puts there. The log of
# zot would not tell: each task up starts a new mirror container, and the
# proxy runs from the first task up on, since task up applies the Gateway.
catalog="$(printf '%s\n' "$probe" | sed -n 's/^catalog: //p')"
for repository in "$PROXY_REPOSITORY" "$POSTGRES_REPOSITORY"; do
  case "$catalog" in
    *"\"$repository\""*) printf 'note: the mirror holds %s: the node pulled it through the mirror.\n' "$repository" ;;
    *) fail "the catalog of the mirror does not list $repository: the node did not pull it through the mirror (catalog: $catalog)" ;;
  esac
done

e2e_finish
