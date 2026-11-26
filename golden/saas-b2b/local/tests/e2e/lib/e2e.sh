# shellcheck shell=bash
# shellcheck disable=SC2034 # the E2E_ values are read by the tests that source this file
# Shared helpers of the tests on kind (spec 001, local/tests/e2e/). Sourced
# by each test, never run on its own. The tests drive the real tasks, task
# up and task down first, against the real container engine and kind:
# local/tests/e2e/run.sh runs them in order, under `task test:e2e`.
#
# The names below are what the tests expect task up to create. They are
# written here on purpose, apart from local/scripts/lib/local-env.sh: a
# change of name there must break a test, not move it along.
#
# Run outside run.sh, a test uses the HOME it gets, so the kubeconfig of the
# project lands in its .kube/. run.sh gives the tests a HOME of their own,
# and sets E2E_SANDBOX_HOME=1.

E2E_ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)"
E2E_CLUSTER="saas-b2b"
E2E_CONTEXT="kind-$E2E_CLUSTER"
E2E_MIRROR="saas-b2b-mirror"
E2E_VOLUME="saas-b2b-mirror"
E2E_LABEL="invalid.saas-b2b.role=registry-mirror"
E2E_KUBECONFIG="${HOME:?}/.kube/kind-$E2E_CLUSTER"
# kind labels each node container with its cluster (kind v0.33.0,
# pkg/cluster/internal/providers/docker/constants.go).
E2E_NODE_FILTER="label=io.x-k8s.kind.cluster=$E2E_CLUSTER"
# The host ports of the gateway, as local/tasks/local.yml and
# local/kind/cluster.yaml set them (research RS-20), and the Gateway of the
# common layer, in the namespace of the application (contracts/layers.md).
E2E_GATEWAY_HTTP_PORT=18080
E2E_GATEWAY_HTTPS_PORT=18443
E2E_APP_NAMESPACE="saas-b2b"
E2E_GATEWAY="saas-b2b"
# The Secrets of the database and their keys (contracts/secrets.md), and the
# user name of db-auth.
E2E_SECRETS="db-auth db-superuser"
E2E_SECRET_KEYS="password username"
E2E_SECRET_TYPE="kubernetes.io/basic-auth"
E2E_APP_USER="app"
# cache-auth (ADR-015, conditions 5 and 19; contracts/secrets.md): Opaque, the
# key password alone. The cache keeps nothing, so it has no volume to check.
E2E_CACHE_SECRET="cache-auth"
E2E_CACHE_SECRET_KEYS="password"
E2E_CACHE_SECRET_TYPE="Opaque"
# Every Secret that holds a drawn password.
E2E_PASSWORD_SECRETS="$E2E_SECRETS $E2E_CACHE_SECRET"
# gateway-tls (research RS-10; contracts/secrets.md): kubernetes.io/tls, the
# keys tls.crt and tls.key. It holds a key and a certificate, no password, so
# E04 and E06 leave it out of the password rules; E05 keeps it with the rest.
E2E_TLS_SECRET="gateway-tls"
E2E_TLS_SECRET_KEYS="tls.crt tls.key"
E2E_TLS_SECRET_TYPE="kubernetes.io/tls"
# Every Secret that a second task up keeps as it is.
E2E_KEPT_SECRETS="$E2E_PASSWORD_SECRETS $E2E_TLS_SECRET"
# The volume of the database: the PVC of the StatefulSet postgres.
E2E_DATA_VOLUME="data-postgres-0"
# A password is 32 characters at least, and none of the known values of
# ADR-007, condition 1, of ADR-012, condition 10 (mysecretpassword) and of
# ADR-015, condition 19 (foobared, password123); the empty value is
# refused by the length.
E2E_MIN_PASSWORD_LENGTH=32
E2E_KNOWN_VALUES="root admin postgres password changeme mysecretpassword foobared password123"

E2E_FAILURES=0
OUTPUT=""
STATUS=0

for tool in task docker kind kubectl openssl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf '%s is not on PATH: the tests on kind need task, docker, kind, kubectl and openssl.\n' "$tool"
    exit 1
  fi
done

fail() {
  E2E_FAILURES=$((E2E_FAILURES + 1))
  printf 'FAIL: %s\n' "$1"
}

# show_output: the output of the last task, indented, for a failure.
show_output() {
  printf '  exit status %s, output:\n' "$STATUS"
  printf '%s\n' "$OUTPUT" | LC_ALL=C cat -v | sed 's/^/    /'
}

# run_task ARG...: runs task ARG... in the golden repo, with the environment
# of the test; sets OUTPUT and STATUS.
run_task() {
  STATUS=0
  OUTPUT="$(CDPATH='' cd -- "$E2E_ROOT" && task "$@" 2>&1)" || STATUS=$?
}

# must_succeed ARG...: runs task ARG..., and fails the test if it fails.
must_succeed() {
  run_task "$@"
  if [ "$STATUS" -ne 0 ]; then
    fail "task $* failed"
    show_output
    return 1
  fi
}

expect_output() {
  case "$OUTPUT" in
    *"$1"*) ;;
    *)
      fail "the output of the last task does not say: $1"
      show_output
      ;;
  esac
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

# sha256_stdin: the SHA-256 of the standard input.
sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{ print $1 }'
  else
    shasum -a 256 | awk '{ print $1 }'
  fi
}

container_exists() {
  docker container inspect --format '{{.Name}}' "$1" >/dev/null 2>&1
}

volume_exists() {
  docker volume inspect --format '{{.Name}}' "$1" >/dev/null 2>&1
}

cluster_exists() {
  kind get clusters 2>/dev/null | grep -qx "$E2E_CLUSTER"
}

# kube_e2e ARG...: kubectl on the cluster of the project, through its
# kubeconfig and its context, as the tasks do (S19).
kube_e2e() {
  kubectl --kubeconfig "$E2E_KUBECONFIG" --context "$E2E_CONTEXT" "$@"
}

# The zot image of the project, as local/tasks/local.yml pins it. The decoys
# of E22 use it, so that no other image is pulled.
mirror_image() {
  awk '$1 == "MIRROR_IMAGE:" { print $2; exit }' "$E2E_ROOT/local/tasks/local.yml"
}

# The image of the proxy that local/platform/envoy-proxy.yaml pins, by tag and
# digest (ADR-005, complement of 2026-11-26); empty when the file pins none.
proxy_image() {
  awk '$1 == "image:" && $2 ~ /\/envoyproxy\/envoy:/ { print $2; exit }' "$E2E_ROOT/local/platform/envoy-proxy.yaml"
}

# The Postgres image of local/data/statefulset.yaml, by tag and digest: the
# client pods of E03 and E12 run it, since the node already holds it and it
# carries bash and psql.
postgres_image() {
  awk '$1 == "image:" && $2 ~ /\/postgres:/ { print $2; exit }' "$E2E_ROOT/local/data/statefulset.yaml"
}

# How long a client pod gets to end, and the pause between two looks.
E2E_CLIENT_WAIT_SECONDS=120
E2E_CLIENT_PAUSE_SECONDS=2

# client_pod NAMESPACE NAME SCRIPT: runs SCRIPT with bash in a pod NAME of
# NAMESPACE, which the test creates first, on the Postgres image, under the
# restricted profile (UID 999, no privilege escalation, no capability,
# seccomp RuntimeDefault, no service account token); waits until it ends,
# then removes it. Sets OUTPUT to its log, and STATUS to 0 when it
# succeeded, 1 otherwise. SCRIPT is an argument of the pod: it never holds a
# secret. E2E_CLIENT_LABELS, when set, is the label list of the pod (a=b,c=d),
# which a NetworkPolicy may select on.
client_pod() {
  local namespace="$1" name="$2" script="$3" image overrides phase="" waited=0 labels=""
  image="$(postgres_image)"
  [ -z "${E2E_CLIENT_LABELS:-}" ] || labels="--labels=$E2E_CLIENT_LABELS"
  overrides='{"apiVersion":"v1","spec":{"automountServiceAccountToken":false,"securityContext":{"runAsNonRoot":true,"runAsUser":999,"runAsGroup":999,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"'"$name"'","securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'
  STATUS=1
  if ! OUTPUT="$(kube_e2e --namespace "$namespace" run "$name" --image="$image" --restart=Never ${labels:+"$labels"} \
    --override-type=strategic --overrides="$overrides" --command -- bash -c "$script" 2>&1)"; then
    return 0
  fi
  while :; do
    phase="$(kube_e2e --namespace "$namespace" get pod "$name" --output 'jsonpath={.status.phase}' 2>/dev/null)" || phase=""
    case "$phase" in
      Succeeded | Failed) break ;;
    esac
    [ "$waited" -lt "$E2E_CLIENT_WAIT_SECONDS" ] || break
    sleep "$E2E_CLIENT_PAUSE_SECONDS"
    waited=$((waited + E2E_CLIENT_PAUSE_SECONDS))
  done
  OUTPUT="$(kube_e2e --namespace "$namespace" logs "$name" 2>&1)" || :
  [ "$phase" = Succeeded ] && STATUS=0
  kube_e2e --namespace "$namespace" delete pod "$name" --ignore-not-found --wait=false >/dev/null 2>&1 || :
}

# client_namespace NAME: creates the namespace NAME of a client pod, under
# the restricted profile.
client_namespace() {
  kube_e2e create namespace "$1" >/dev/null &&
    kube_e2e label namespace "$1" pod-security.kubernetes.io/enforce=restricted >/dev/null
}

# remove_client_namespace NAME: removes it, and does not wait.
remove_client_namespace() {
  kube_e2e delete namespace "$1" --ignore-not-found --wait=false >/dev/null 2>&1 || :
}

# db_query SECRET DATABASE SQL: runs SQL with psql in the container of
# Postgres, as the user of the Secret SECRET (db-auth or db-superuser), on
# DATABASE, through the Service, in unaligned rows. The password goes from
# the file of the Secret, mounted in the pod, to the environment of psql
# there; it never reaches this machine. Prints the rows; fails as psql does.
db_query() {
  # shellcheck disable=SC2016 # expanded by bash in the pod
  kube_e2e --namespace "$E2E_APP_NAMESPACE" exec postgres-0 --container postgres -- \
    bash -c 'PGPASSWORD="$(cat "/run/secrets/$1/password")" exec psql --host=postgres --port=5432 --username="$(cat "/run/secrets/$1/username")" --dbname="$2" --no-password --no-psqlrc --tuples-only --no-align --field-separator="|" --set=ON_ERROR_STOP=1 --command="$3"' \
    db-query "$1" "$2" "$3"
}

# secret_value SECRET KEY: the decoded value of KEY in the Secret SECRET of
# the namespace of the application. The tests keep it in memory and never
# print it.
secret_value() {
  kube_e2e --namespace "$E2E_APP_NAMESPACE" get secret "$1" --output "go-template={{index .data \"$2\" | base64decode}}"
}

# cert_fingerprint: reads a PEM certificate on the standard input and prints
# its SHA-256 fingerprint as 64 upper-case hexadecimal digits, empty when the
# input holds no certificate. OpenSSL and LibreSSL write the line differently
# ("sha256 Fingerprint=" or "SHA256 Fingerprint=", digits in pairs with
# colons): only the digits are kept.
cert_fingerprint() {
  openssl x509 -noout -fingerprint -sha256 2>/dev/null | sed -n 's/^.*Fingerprint=//p' | tr -d ':' | tr 'a-f' 'A-F'
}

# tls_pair_matches: succeeds when the key of gateway-tls is the key of its
# certificate: the public key that each holds is the same. Only public keys
# reach this shell; the private key goes through a pipe to openssl.
tls_pair_matches() {
  local from_cert from_key
  from_cert="$(secret_value "$E2E_TLS_SECRET" tls.crt | openssl x509 -noout -pubkey 2>/dev/null)" || return 1
  from_key="$(secret_value "$E2E_TLS_SECRET" tls.key | openssl pkey -pubout 2>/dev/null)" || return 1
  [ -n "$from_cert" ] && [ "$from_cert" = "$from_key" ]
}

# The host name that the HTTPRoutes of the local layer accept, and that task
# up prints in the addresses (tasks.md, gap 141). Gateway API refuses an IP
# in hostnames, so the address of the user is localhost, not 127.0.0.1; the
# port stays published on 127.0.0.1 alone.
E2E_HOST="localhost"

# The registries whose images the node pulls through the mirror, and the
# host of the images that task up builds (research RS-07).
E2E_BUILT_HOST="saas-b2b.invalid"
E2E_API_DEPLOYMENT="api"
E2E_FRONT_DEPLOYMENT="front"

# How long a read on the gateway waits for a byte, and how long wait_http
# keeps asking.
E2E_HTTP_READ_SECONDS=10
HTTP_STATUS=""
HTTP_BODY=""

# decode_chunked: the body of a chunked answer on the standard input, one
# chunk of the data per line (the JSON of the API holds no line feed), and
# its decoded text on the standard output.
decode_chunked() {
  local line decoded=""
  while IFS= read -r line; do
    line="${line%$'\r'}"
    [[ $line =~ ^[0-9a-fA-F]+ ]] || break
    [ "$((16#${BASH_REMATCH[0]}))" -gt 0 ] || break
    IFS= read -r line || true
    decoded="$decoded${line%$'\r'}"
  done
  printf '%s' "$decoded"
}

# http_request METHOD PATH [BODY]: one request to the gateway, on
# 127.0.0.1 and the HTTP port, with the Host header of the HTTPRoutes, read
# by bash itself through /dev/tcp (no curl). A BODY is sent as JSON; the Host
# header is E2E_REQUEST_HOST when set. Sets
# HTTP_STATUS and HTTP_BODY; fails without an HTTP answer. Written for
# bash 3.2: the answer is read line by line, each read bounded.
http_request() {
  local method="$1" path="$2" body="${3:-}" response status_line headers lowered
  HTTP_STATUS=""
  HTTP_BODY=""
  response="$(
    exec 3<>"/dev/tcp/127.0.0.1/$E2E_GATEWAY_HTTP_PORT" || exit 1
    if [ -n "$body" ]; then
      printf '%s %s HTTP/1.1\r\nHost: %s\r\nConnection: close\r\nContent-Type: application/json\r\nContent-Length: %s\r\n\r\n%s' \
        "$method" "$path" "${E2E_REQUEST_HOST:-$E2E_HOST}" "${#body}" "$body" >&3
    else
      printf '%s %s HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n' "$method" "$path" "${E2E_REQUEST_HOST:-$E2E_HOST}" >&3
    fi
    while :; do
      rc=0
      IFS= read -r -t "$E2E_HTTP_READ_SECONDS" line <&3 || rc=$?
      if [ "$rc" -gt 128 ]; then
        break
      fi
      if [ "$rc" -ne 0 ]; then
        printf '%s' "$line"
        break
      fi
      printf '%s\n' "$line"
    done
  )" 2>/dev/null || return 1
  status_line="${response%%$'\n'*}"
  [[ $status_line =~ ^HTTP/1\.[01]\ ([0-9][0-9][0-9]) ]] || return 1
  HTTP_STATUS="${BASH_REMATCH[1]}"
  headers="${response%%$'\r\n\r\n'*}"
  [ "$headers" != "$response" ] || return 0
  HTTP_BODY="${response#*$'\r\n\r\n'}"
  lowered="$(printf '%s' "$headers" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
  case "$lowered" in
    *'transfer-encoding: chunked'*) HTTP_BODY="$(printf '%s' "$HTTP_BODY" | decode_chunked)" ;;
  esac
}

# wait_http METHOD PATH STATUS SECONDS [BODY]: asks every two seconds until
# the gateway answers STATUS, for SECONDS at most; true when it did.
wait_http() {
  local waited=0
  while :; do
    if http_request "$1" "$2" "${5:-}" && [ "$HTTP_STATUS" = "$3" ]; then
      return 0
    fi
    [ "$waited" -lt "$4" ] || return 1
    sleep 2
    waited=$((waited + 2))
  done
}

# json_field NAME: the string value of NAME in the JSON of HTTP_BODY; empty
# when the field is absent. The API writes compact JSON in camelCase.
json_field() {
  printf '%s' "$HTTP_BODY" | sed -n 's/.*"'"$1"'":"\([^"]*\)".*/\1/p'
}

e2e_finish() {
  if [ "$E2E_FAILURES" -gt 0 ]; then
    printf '%s failure(s).\n' "$E2E_FAILURES"
    exit 1
  fi
  printf 'passed.\n'
}
