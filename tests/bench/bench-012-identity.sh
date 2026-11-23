#!/usr/bin/env bash
# BENCH-012: identity provider of the standard profile, in the local kind
# cluster of the generated project.
#
# Inventory of the commands that create, modify or delete a container or a
# network ([SECU] rule of 2026-11-20). No other line of this script does:
#   kind create cluster --name celian-bench-012 ...
#       creates the node container celian-bench-012-control-plane, and the
#       "kind" Docker network if it does not exist yet (kind's own calls);
#   kind delete cluster --name celian-bench-012 ...
#       deletes that container;
#   docker network rm kind
#       in the EXIT trap only, and only if this script created the network and
#       no container uses it any more.
# No docker run, start, restart, exec, cp, build or pull. The other docker
# calls only read: docker version, docker info, docker ps -q, docker stats
# --no-stream, docker network inspect, docker manifest inspect -v (registry
# metadata, no pull). Inside the cluster, kubectl creates and deletes pods
# that the node's containerd runs; they are not containers of the host.
# No curl, wget, python, node or perl: HTTP requests go through
# bench-012/client/http.sh (busybox nc) in a client pod, and the token
# signature is checked on the host with openssl.
#
# Options:
#   keycloak  Keycloak 26.8.2, `start --import-realm`, manifest derived from
#             the quickstart of keycloak/keycloak-quickstarts
#             (bench-012/keycloak/);
#   zitadel   ZITADEL v4.20.5, chart 10.5.0 rendered once by helm template
#             (bench-012/zitadel/), API and Login V2;
#   none      the base node: kind, the shared Postgres of the stack (option
#             "statefulset" of BENCH-011) and the client pod, no provider.
# Each run creates a fresh kind cluster (kind 0.33.0, node image pinned by
# digest, ADR-004), starts the shared Postgres and creates in it a role and a
# database for the provider, then measures:
#   M1  installation until "ready": from the first kubectl apply of the layer
#       to the first of three valid answers of the OIDC discovery document,
#       through the Service, from the client pod (one try per second);
#   M2  memory at rest, IDLE_WAIT seconds after "ready", client pod scaled to
#       zero: node container (docker stats) and pods of the layer (kubelet
#       Summary API), 3 samples 10 s apart; the layer is the node minus the
#       base node (M9), medians;
#   M3  CPU of the pods of the layer, same samples;
#   M4  compressed size of the images of the layer per architecture, read at
#       the registry;
#   M5  images of the layer pulled by the node at each run (Pulled events);
#   M6  a token for the test client, checked against the keys the issuer
#       publishes (RS256 signature, issuer, expiry);
#   M7  back to "ready" after the provider pod is deleted, then a new token;
#   M8  no default administrator credential: the known values of ADR-007
#       (plus the vendors' documented defaults) are refused, and the value of
#       the Secret created by a pipe is accepted.
# Runs are interleaved (option A, option B, ..., then the next run).
#
# Usage: caffeinate -i -s tests/bench/bench-012-identity.sh [TRIAL_DIR]
#   On macOS, caffeinate keeps the host awake: a sleeping host stalls the
#   cluster, and the script then fails instead of recording wrong timings.
#   TRIAL_DIR, if given, must be missing or empty (default: a new mktemp -d).
#   Environment:
#     OPTIONS="none keycloak zitadel"  options, interleaved in order
#     RUNS=3            runs per option
#     IDLE_WAIT=120     seconds between "ready" and the first sample
#     BENCH_LOCK=DIR    lock directory shared with other benchmarks, created
#                       with mkdir after the start-up checks (exit code 75 if
#                       it exists), removed by the EXIT trap
#     KEEP_CLUSTER=0    1 keeps the last cluster for inspection (debug only)
#   Results (TSV) in TRIAL_DIR: versions.tsv, files.tsv, images.tsv, runs.tsv,
#   idle-pods.tsv, node-images.tsv, oidc.tsv, admin.tsv, load.tsv,
#   summary.tsv; command output in TRIAL_DIR/logs/. No secret value, token
#   or key is written there.
# Needs: bash >= 3.2, docker, kind v0.33.0, kubectl (1.35 to 1.37), gh, jq,
#   gdate (GNU coreutils), openssl, xxd, shasum, awk.
set -euo pipefail
umask 077

# --- Pinned versions ----------------------------------------------------------

readonly KIND_VERSION="v0.33.0"
readonly KIND_IMAGE="kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed"
readonly KUBECTL_MINORS="35 36 37"

# Shared Postgres of the stack: option "statefulset" of BENCH-011.
readonly PG_IMAGE="docker.io/library/postgres:18.7-trixie@sha256:eb63372c1e05c755f55fa30cbd07aecc443676fc6c0fa90b9002d01537841e1a"
# Client pod: busybox, for sh and nc.
readonly CLIENT_IMAGE="docker.io/library/busybox:1.37.0@sha256:a7dbc319b1438115a207e11930dc4bb3e643dcb3ec0bdd694bb36cd8fad289ec"

readonly KC_VERSION="26.8.2"
readonly KC_IMAGE="quay.io/keycloak/keycloak:26.8.2@sha256:7e66a96e4739239070aeaf72e4c5decf0f7f682cfc725b9f7ea2b336eaba38b3"
readonly KC_QUICKSTART_COMMIT="c598d34d3b2dd85976ac96614176df351ee1a4d5"
readonly KC_QUICKSTART_SHA256="b4de5e35b234c11400192e805d4cb551c51e358f655be2196a51c2f9171fb9af"

readonly ZITADEL_VERSION="v4.20.5"
readonly ZITADEL_CHART="10.5.0"
readonly ZITADEL_CHART_TGZ_SHA256="e216ca1a9b19e9e2982e76a2cf49c446eeb3a02cdf167834977978acb880f019"
readonly ZITADEL_IMAGES="
ghcr.io/zitadel/zitadel:v4.20.5@sha256:cb21fe73badfe44972bb24a66cf0ebce6a8dc63ab8ed24567af6b731bd8bbf45
ghcr.io/zitadel/zitadel-login:v4.20.5@sha256:bbab3b26a44093c1a9636a6b89c3ab31c2f6eb2f2cafc681c6f676e74e96845c
docker.io/alpine/k8s:1.36.4@sha256:358ddfc2d6ff3f00dd461dbd79aaa6d6738709f225b8da0945bb63bd4dbc304e
docker.io/wait4x/wait4x:3.6@sha256:bec7ac18547781d854562c3729d3195c3880116d6758c49fdf4573ad58805f14
"

# Directories of bench-012/ whose files the cluster receives; the SHA-256 of
# every file goes to files.tsv.
readonly LAYER_DIRS="keycloak zitadel client"

readonly CLUSTER="celian-bench-012"
readonly NODE="$CLUSTER-control-plane"
readonly NS_DB="bench-db"
readonly NS_IDP="bench-idp"
readonly SAMPLES=3
readonly SAMPLE_GAP=10
readonly PAUSE_BETWEEN_RUNS=15
readonly READY_STREAK=3
readonly CLUSTER_TIMEOUT=300
readonly READY_TIMEOUT=900
readonly SECRET_TIMEOUT=300
readonly MAX_CLOCK_DRIFT=30
# Known values of ADR-007, condition 1, plus the documented defaults of the
# two options (Keycloak quickstart: admin; ZITADEL steps.yaml: Password1!).
# EMPTY stands for the empty string.
readonly KNOWN_VALUES="root admin postgres password changeme EMPTY Password1!"

OPTIONS="${OPTIONS:-none keycloak zitadel}"
RUNS="${RUNS:-3}"
IDLE_WAIT="${IDLE_WAIT:-120}"
BENCH_LOCK="${BENCH_LOCK:-}"
KEEP_CLUSTER="${KEEP_CLUSTER:-0}"
readonly OPTIONS RUNS IDLE_WAIT BENCH_LOCK KEEP_CLUSTER

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
readonly DATA_DIR="$SCRIPT_DIR/bench-012"
TRIAL_DIR=""
LOGS=""
LOCK_HELD=0
KIND_NETWORK_EXISTED=0

# --- Helpers ------------------------------------------------------------------

log() { printf '[bench-012 %s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die() {
  log "ERROR: $*"
  exit 1
}
now() { gdate +%s.%3N; }
seconds_between() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", b - a }'; }
utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

tsv() {
  local file=$1
  shift
  local IFS=$'\t'
  printf '%s\n' "$*" >>"$TRIAL_DIR/$file"
}

median_range() {
  sort -n | awk '{ v[NR] = $1 } END {
    if (NR == 0) { print "-\t-"; exit }
    m = (NR % 2) ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2
    printf "%.1f\t%.1f\n", m, v[NR] - v[1] }'
}

kube() { kubectl --request-timeout=30s "$@"; }

# Print the time of the first of READY_STREAK consecutive successes of a
# command, polled every second, or fail after TIMEOUT seconds.
wait_streak() {
  local timeout=$1 deadline streak=0 first="" t
  shift
  deadline=$(($(date +%s) + timeout))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    t=$(now)
    if "$@"; then
      if [ "$streak" -eq 0 ]; then first=$t; fi
      streak=$((streak + 1))
      if [ "$streak" -ge "$READY_STREAK" ]; then
        echo "$first"
        return 0
      fi
    else
      streak=0
    fi
    sleep 1
  done
  return 1
}

wait_until() {
  local timeout=$1 deadline
  shift
  deadline=$(($(date +%s) + timeout))
  until "$@"; do
    [ "$(date +%s)" -lt "$deadline" ] || return 1
    sleep 1
  done
}

# A random value of LENGTH characters from /dev/urandom, on stdout only.
random_value() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$1"; }

# --- Options ------------------------------------------------------------------

option_version() {
  case $1 in
    keycloak) echo "$KC_VERSION" ;;
    zitadel) echo "$ZITADEL_VERSION (chart $ZITADEL_CHART)" ;;
    none) echo "-" ;;
  esac
}

option_images() {
  case $1 in
    keycloak) echo "$KC_IMAGE" ;;
    zitadel) printf '%s\n' "$ZITADEL_IMAGES" | grep . ;;
  esac
}

# Service of the provider, Host header, and path of the discovery document.
idp_service() {
  case $1 in
    keycloak) echo "keycloak:8080" ;;
    zitadel) echo "zitadel:8080" ;;
  esac
}

idp_host_header() {
  case $1 in
    keycloak) echo "keycloak:8080" ;;
    zitadel) echo "idp.bench.test:8080" ;;
  esac
}

idp_discovery_path() {
  case $1 in
    keycloak) echo "/realms/bench/.well-known/openid-configuration" ;;
    zitadel) echo "/.well-known/openid-configuration" ;;
  esac
}

# Pods of the provider deleted for M7.
idp_pod_selector() {
  case $1 in
    keycloak) echo "app=keycloak" ;;
    zitadel) echo "app.kubernetes.io/name=zitadel,app.kubernetes.io/component=start" ;;
  esac
}

db_role() {
  case $1 in
    keycloak) echo "keycloak" ;;
    zitadel) echo "zitadel" ;;
  esac
}

# --- Files ----------------------------------------------------------------------

file_sum() { shasum -a 256 "$1" | awk '{ print $1 }'; }

# Check the reference manifest of Keycloak and record the SHA-256 of every
# file of bench-012/ that the cluster receives.
check_files() {
  local ref rel sum
  ref="$TRIAL_DIR/keycloak-quickstart.yaml"
  gh api -H 'Accept: application/vnd.github.raw' \
    "repos/keycloak/keycloak-quickstarts/contents/kubernetes/keycloak.yaml?ref=$KC_QUICKSTART_COMMIT" \
    >"$ref" 2>>"$LOGS/files.log" || die "keycloak quickstart download failed"
  sum=$(file_sum "$ref")
  [ "$sum" = "$KC_QUICKSTART_SHA256" ] || die "keycloak quickstart: SHA-256 $sum differs from $KC_QUICKSTART_SHA256"
  tsv files.tsv reference "keycloak-quickstarts@$KC_QUICKSTART_COMMIT kubernetes/keycloak.yaml" "$sum"
  # shellcheck disable=SC2086 # LAYER_DIRS is a list of directory names
  for rel in $(cd "$DATA_DIR" && find $LAYER_DIRS -type f | LC_ALL=C sort); do
    [ -f "$DATA_DIR/$rel" ] || die "missing $DATA_DIR/$rel"
    tsv files.tsv layer "$rel" "$(file_sum "$DATA_DIR/$rel")"
  done
  tsv files.tsv chart "zitadel-$ZITADEL_CHART.tgz (rendered into zitadel/rendered/)" "$ZITADEL_CHART_TGZ_SHA256"
  check_pinned "$DATA_DIR"/keycloak/statefulset.yaml "$DATA_DIR"/zitadel/rendered/*.yaml
}

check_pinned() {
  local unpinned
  unpinned=$(sed -n -E 's/^[[:space:]]*(-[[:space:]]+)?image:[[:space:]]+"?([^"[:space:]]+)"?[[:space:]]*$/\2/p' "$@" |
    grep -v '@sha256:' || true)
  [ -z "$unpinned" ] || die "images without a pinned digest: $unpinned"
}

# --- Base: shared Postgres and client pod -------------------------------------------

namespaces_manifest() {
  printf 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: %s\n---\n' "$NS_DB"
  printf 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: %s\n' "$NS_IDP"
}

# Option "statefulset" of BENCH-011, unchanged.
postgres_manifest() {
  cat <<EOF
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: $NS_DB
spec:
  selector: {app: postgres}
  ports: [{port: 5432, targetPort: 5432}]
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: $NS_DB
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels: {app: postgres}
  template:
    metadata:
      labels: {app: postgres}
    spec:
      securityContext: {runAsNonRoot: true, runAsUser: 999, runAsGroup: 999, fsGroup: 999}
      containers:
        - name: postgres
          image: $PG_IMAGE
          ports: [{containerPort: 5432}]
          env:
            - {name: POSTGRES_USER_FILE, value: /run/secrets/db/username}
            - {name: POSTGRES_PASSWORD_FILE, value: /run/secrets/db/password}
            - {name: POSTGRES_DB, value: app}
          readinessProbe:
            exec: {command: [pg_isready, -U, app, -d, app]}
            periodSeconds: 2
          securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}}
          volumeMounts:
            - {name: data, mountPath: /var/lib/postgresql}
            - {name: auth, mountPath: /run/secrets/db, readOnly: true}
      volumes:
        - name: auth
          secret: {secretName: db-auth, defaultMode: 0440}
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: [ReadWriteOnce]
        resources:
          requests: {storage: 1Gi}
EOF
}

client_manifest() {
  cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: client
  namespace: $NS_IDP
spec:
  replicas: 1
  selector:
    matchLabels: {app: client}
  template:
    metadata:
      labels: {app: client}
    spec:
      terminationGracePeriodSeconds: 1
      securityContext: {runAsNonRoot: true, runAsUser: 65534, runAsGroup: 65534}
      containers:
        - name: client
          image: $CLIENT_IMAGE
          command: [sh, -c, "trap 'exit 0' TERM; while :; do sleep 1; done"]
          env:
            - name: ADMIN_PASSWORD
              valueFrom: {secretKeyRef: {name: idp-admin, key: password, optional: true}}
            - name: CLIENT_SECRET
              valueFrom: {secretKeyRef: {name: idp-client, key: secret, optional: true}}
          securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}}
          volumeMounts:
            - {name: http, mountPath: /bench, readOnly: true}
      volumes:
        - name: http
          configMap: {name: bench-http}
EOF
}

# Every Secret value comes from /dev/urandom through a pipe to kubectl
# create -f -: never in a file, an argument or a variable of the script.
create_secret() {
  local ns=$1 name=$2 key=$3 length=$4 suffix=${5:-} extra=${6:-}
  {
    printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: %s\n  namespace: %s\nstringData:\n' "$name" "$ns"
    if [ -n "$extra" ]; then printf '  %s\n' "$extra"; fi
    printf '  %s: "' "$key"
    random_value "$length"
    printf '%s"\n' "$suffix"
  } | kube create -f -
}

secret_value() {
  kube get secret "$2" -n "$1" -o "jsonpath={.data.$3}" | base64 -d
}

postgres_ready() {
  [ "$(kube exec -n "$NS_DB" postgres-0 -c postgres -- psql -X -U app -d app -tAc 'select 1' 2>/dev/null | tr -d '[:space:]')" = 1 ]
}

client_ready() {
  [ "$(kube get deployment client -n "$NS_IDP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = 1 ]
}

start_base() {
  local log_file=$1
  namespaces_manifest | kube apply -f - >>"$log_file" 2>&1
  create_secret "$NS_DB" db-auth password 40 "" "username: app" >>"$log_file" 2>&1 || die "db-auth secret failed"
  postgres_manifest | kube apply -f - >>"$log_file" 2>&1
  wait_until "$READY_TIMEOUT" postgres_ready || die "shared postgres not ready"
  kube create configmap bench-http -n "$NS_IDP" --from-file=http.sh="$DATA_DIR/client/http.sh" >>"$log_file" 2>&1
}

start_client() {
  local log_file=$1
  client_manifest | kube apply -f - >>"$log_file" 2>&1
  wait_until 300 client_ready || die "client pod not ready"
}

# The role and the database of the provider, in the shared Postgres. The
# password goes from the Secret to psql through a pipe.
prepare_database() {
  local opt=$1 role
  role=$(db_role "$opt")
  create_secret "$NS_IDP" idp-db password 40 "" "username: $role"
  {
    printf "CREATE ROLE %s LOGIN PASSWORD '" "$role"
    secret_value "$NS_IDP" idp-db password
    printf "';\nCREATE DATABASE %s OWNER %s;\n" "$role" "$role"
  } | kube exec -i -n "$NS_DB" postgres-0 -c postgres -- psql -X -q -U app -d app -v ON_ERROR_STOP=1
}

# Secrets of each option, created before the layer is applied.
prepare_secrets() {
  local opt=$1
  # 36 random characters, then "a.Z9": ZITADEL's default password policy
  # wants a lower case letter, an upper case letter, a digit and a symbol.
  create_secret "$NS_IDP" idp-admin password 36 "a.Z9"
  case $opt in
    keycloak)
      create_secret "$NS_IDP" idp-client secret 40
      ;;
    zitadel)
      create_secret "$NS_IDP" zitadel-masterkey masterkey 32
      {
        printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: zitadel-env\n  namespace: %s\nstringData:\n' "$NS_IDP"
        printf '  ZITADEL_DATABASE_POSTGRES_DSN: "host=postgres.%s.svc.cluster.local port=5432 user=zitadel dbname=zitadel sslmode=disable password=' "$NS_DB"
        secret_value "$NS_IDP" idp-db password
        printf '"\n  ZITADEL_FIRSTINSTANCE_ORG_HUMAN_PASSWORD: "'
        secret_value "$NS_IDP" idp-admin password
        printf '"\n'
      } | kube create -f -
      create_login_key
      ;;
  esac
}

# RSA key pair of the ZITADEL Login V2 (SystemAPIUsers). The key stays in
# memory, from openssl to the pipe that creates the Secret.
create_login_key() {
  local key crt
  key=$(openssl genrsa 2048 2>/dev/null)
  crt=$(printf '%s\n' "$key" | openssl req -new -x509 -key /dev/stdin -subj /CN=login-client -days 2 2>/dev/null)
  {
    printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: zitadel-login-key\n  namespace: %s\ntype: kubernetes.io/tls\ndata:\n  tls.crt: ' "$NS_IDP"
    printf '%s\n' "$crt" | base64 | tr -d '\n'
    printf '\n  tls.key: '
    printf '%s\n' "$key" | base64 | tr -d '\n'
    printf '\n'
  } | kube create -f -
  key=""
  crt=""
}

apply_layer() { kube apply -k "$DATA_DIR/$1"; }

# --- HTTP from the client pod -----------------------------------------------------

# http METHOD PATH [HEADER...] for the provider of option $HTTP_OPT; the body,
# if any, comes from stdin.
http() {
  local method=$1 path=$2
  shift 2
  kube exec -i -n "$NS_IDP" deploy/client -- sh /bench/http.sh "$method" \
    "$(idp_service "$HTTP_OPT")" "$(idp_host_header "$HTTP_OPT")" "$path" "$@"
}

http_status() { head -n 1 | awk '{ print $2 }'; }
http_body() { awk 'body { print } /^\r?$/ { body = 1 }'; }

discovery_ok() {
  local resp
  resp=$(http GET "$(idp_discovery_path "$HTTP_OPT")" </dev/null 2>/dev/null) || return 1
  [ "$(printf '%s\n' "$resp" | http_status)" = 200 ] || return 1
  printf '%s\n' "$resp" | http_body | jq -e '.issuer | type == "string" and length > 0' >/dev/null 2>&1
}

discovery_json() { http GET "$(idp_discovery_path "$HTTP_OPT")" </dev/null | http_body; }

url_path() { printf '%s' "$1" | sed -E 's#^https?://[^/]*##'; }

# --- M6: token and signature ------------------------------------------------------

# Keycloak: client credentials of the test client of the imported realm. The
# secret is read from the client pod's environment, inside the pod.
token_keycloak() {
  # shellcheck disable=SC2016 # expanded in the pod
  kube exec -i -n "$NS_IDP" deploy/client -- sh -c '
    printf "grant_type=client_credentials&client_id=bench-client&client_secret=%s" "$CLIENT_SECRET" |
      sh /bench/http.sh POST keycloak:8080 keycloak:8080 /realms/bench/protocol/openid-connect/token \
        "Content-Type: application/x-www-form-urlencoded"' </dev/null
}

# ZITADEL: no declarative client at setup. With the PAT that the setup Job
# wrote, the pod creates (once) a machine user with JWT access tokens, gives
# it a new secret, and asks for a token with it. The PAT arrives on stdin;
# the client secret never leaves the pod. Prints "uid=<id>", then the token
# response.
token_zitadel() {
  local uid=${1:-}
  # shellcheck disable=SC2016 # expanded in the pod
  secret_value "$NS_IDP" iam-admin-pat pat |
    kube exec -i -n "$NS_IDP" deploy/client -- sh -c '
      read -r pat
      req() { sh /bench/http.sh "$1" zitadel:8080 idp.bench.test:8080 "$2" "Content-Type: application/json" "Authorization: Bearer $pat"; }
      uid="'"$uid"'"
      if [ -z "$uid" ]; then
        r=$(printf "%s" "{\"userName\":\"bench-client\",\"name\":\"bench-client\",\"accessTokenType\":\"ACCESS_TOKEN_TYPE_JWT\"}" | req POST /management/v1/users/machine)
        uid=$(printf "%s" "$r" | sed -n "s/.*\"userId\":\"\([^\"]*\)\".*/\1/p")
      fi
      echo "uid=$uid"
      r=$(printf "{}" | req PUT "/management/v1/users/$uid/secret")
      cid=$(printf "%s" "$r" | sed -n "s/.*\"clientId\":\"\([^\"]*\)\".*/\1/p")
      cs=$(printf "%s" "$r" | sed -n "s/.*\"clientSecret\":\"\([^\"]*\)\".*/\1/p")
      basic=$(printf "%s:%s" "$cid" "$cs" | base64 | tr -d "\n")
      printf "grant_type=client_credentials&scope=openid" |
        sh /bench/http.sh POST zitadel:8080 idp.bench.test:8080 /oauth/v2/token \
          "Content-Type: application/x-www-form-urlencoded" "Authorization: Basic $basic"'
}

b64url_decode() {
  local s
  s=$(tr '_-' '/+')
  case $((${#s} % 4)) in
    2) s="$s==" ;;
    3) s="$s=" ;;
  esac
  printf '%s' "$s" | openssl base64 -d -A
}

# Check a JWT against the JWKS of the issuer. Prints a TSV fragment:
# result, alg, kid, issuer match, expiry ok, audience claims. The token and
# the signed data only live in a private temporary directory, removed here.
verify_jwt() {
  local token=$1 jwks=$2 issuer=$3 tmp header payload alg kid n e iss exp aud result=no iss_ok=no exp_ok=no
  tmp=$(mktemp -d "$TRIAL_DIR/tmp.XXXXXX")
  header=$(printf '%s' "${token%%.*}" | b64url_decode)
  payload=$(printf '%s' "$token" | cut -d. -f2 | b64url_decode)
  alg=$(printf '%s' "$header" | jq -r '.alg')
  kid=$(printf '%s' "$header" | jq -r '.kid')
  n=$(printf '%s' "$jwks" | jq -r --arg k "$kid" '.keys[] | select(.kid == $k) | .n')
  e=$(printf '%s' "$jwks" | jq -r --arg k "$kid" '.keys[] | select(.kid == $k) | .e')
  iss=$(printf '%s' "$payload" | jq -r '.iss')
  exp=$(printf '%s' "$payload" | jq -r '.exp')
  aud=$(printf '%s' "$payload" | jq -c '{aud, azp, client_id}')
  [ "$iss" = "$issuer" ] && iss_ok=yes
  [ "$exp" -gt "$(date +%s)" ] 2>/dev/null && exp_ok=yes
  if [ "$alg" = RS256 ] && [ -n "$n" ] && [ -n "$e" ]; then
    printf 'asn1=SEQUENCE:pubkey\n[pubkey]\nn=INTEGER:0x%s\ne=INTEGER:0x%s\n' \
      "$(printf '%s' "$n" | b64url_decode | xxd -p | tr -d '\n')" \
      "$(printf '%s' "$e" | b64url_decode | xxd -p | tr -d '\n')" >"$tmp/key.conf"
    openssl asn1parse -genconf "$tmp/key.conf" -out "$tmp/key.der" -noout >/dev/null 2>&1 &&
      openssl rsa -RSAPublicKey_in -inform DER -in "$tmp/key.der" -pubout -out "$tmp/key.pem" >/dev/null 2>&1
    printf '%s' "${token%.*}" >"$tmp/data"
    printf '%s' "${token##*.}" | b64url_decode >"$tmp/sig"
    if openssl dgst -sha256 -verify "$tmp/key.pem" -signature "$tmp/sig" "$tmp/data" >/dev/null 2>&1; then
      result=yes
    fi
  fi
  rm -f "$tmp/key.conf" "$tmp/key.der" "$tmp/key.pem" "$tmp/data" "$tmp/sig"
  rmdir "$tmp"
  [ "$iss_ok" = yes ] && [ "$exp_ok" = yes ] || result=no
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$result" "$alg" "$kid" "$iss_ok" "$exp_ok" "$aud"
}

# One M6 check. Prints the verification fragment; for ZITADEL, sets ZI_UID.
oidc_check() {
  local opt=$1 step=$2 run=$3 disc issuer jwks resp status token out
  disc=$(discovery_json)
  issuer=$(printf '%s' "$disc" | jq -r '.issuer')
  jwks=$(http GET "$(url_path "$(printf '%s' "$disc" | jq -r '.jwks_uri')")" </dev/null | http_body)
  case $opt in
    keycloak) resp=$(token_keycloak 2>>"$LOGS/oidc.log") || true ;;
    zitadel)
      resp=$(token_zitadel "$ZI_UID" 2>>"$LOGS/oidc.log") || true
      ZI_UID=$(printf '%s\n' "$resp" | sed -n 's/^uid=//p' | head -n 1)
      resp=$(printf '%s\n' "$resp" | sed '/^uid=/d')
      ;;
  esac
  status=$(printf '%s\n' "$resp" | http_status)
  token=$(printf '%s\n' "$resp" | http_body | jq -r '.access_token // empty' 2>/dev/null || true)
  if [ -n "$token" ]; then
    out=$(verify_jwt "$token" "$jwks" "$issuer")
  else
    out=$(printf 'no\t-\t-\t-\t-\t%s' "$(printf '%s\n' "$resp" | http_body | tr -d '\t\n' | cut -c1-200)")
  fi
  token=""
  resp=""
  tsv oidc.tsv "$opt" "$run" "$step" "$status" "$issuer" "$out"
  log "$opt run $run: oidc $step: status $status, signature check: $(printf '%s' "$out" | cut -f1)"
}

# --- M8: administrator credentials ----------------------------------------------

# Keycloak: password grant on the master realm with admin-cli, the client of
# the admin CLI. Prints "label status" per attempt.
admin_keycloak() {
  # shellcheck disable=SC2016 # expanded in the pod
  kube exec -i -n "$NS_IDP" deploy/client -- sh -c '
    try() {
      s=$(printf "grant_type=password&client_id=admin-cli&username=admin&password=%s" "$2" |
        sh /bench/http.sh POST keycloak:8080 keycloak:8080 /realms/master/protocol/openid-connect/token \
          "Content-Type: application/x-www-form-urlencoded" | head -n 1 | awk "{ print \$2 }")
      echo "$1 $s"
    }
    for v in '"$KNOWN_VALUES"'; do
      if [ "$v" = EMPTY ]; then try "$v" ""; else try "$v" "$v"; fi
    done
    try secret "$ADMIN_PASSWORD"' </dev/null
}

# ZITADEL: session API (POST /v2/sessions) with a user check and a password
# check for the human administrator of the first instance, called with the
# PAT of the setup Job (stdin).
admin_zitadel() {
  # shellcheck disable=SC2016 # expanded in the pod
  secret_value "$NS_IDP" iam-admin-pat pat |
    kube exec -i -n "$NS_IDP" deploy/client -- sh -c '
      read -r pat
      try() {
        s=$(printf "{\"checks\":{\"user\":{\"loginName\":\"zitadel-admin@zitadel.idp.bench.test\"},\"password\":{\"password\":\"%s\"}}}" "$2" |
          sh /bench/http.sh POST zitadel:8080 idp.bench.test:8080 /v2/sessions \
            "Content-Type: application/json" "Authorization: Bearer $pat" | head -n 1 | awk "{ print \$2 }")
        echo "$1 $s"
      }
      for v in '"$KNOWN_VALUES"'; do
        if [ "$v" = EMPTY ]; then try "$v" ""; else try "$v" "$v"; fi
      done
      try secret "$ADMIN_PASSWORD"'
}

admin_check() {
  local opt=$1 run=$2 lines label status refused=0 accepted=no total=0
  case $opt in
    keycloak) lines=$(admin_keycloak 2>>"$LOGS/admin.log") || true ;;
    zitadel) lines=$(admin_zitadel 2>>"$LOGS/admin.log") || true ;;
  esac
  while read -r label status; do
    [ -n "$label" ] || continue
    tsv admin.tsv "$opt" "$run" "$label" "${status:--}"
    if [ "$label" = secret ]; then
      case $status in 200 | 201) accepted=yes ;; esac
    else
      total=$((total + 1))
      case $status in 200 | 201) ;; *) refused=$((refused + 1)) ;; esac
    fi
  done <<EOF
$lines
EOF
  log "$opt run $run: admin check: $refused/$total known values refused, secret accepted: $accepted"
  printf '%s/%s\t%s' "$refused" "$total" "$accepted"
}

# --- Cluster ----------------------------------------------------------------------

# shellcheck disable=SC2016 # jq variables, not shell ones
readonly KUBE_SYSTEM_READY='
  [.items[] | select(.kind == "Pod")] as $pods
  | ($pods | length) > 0
  and all($pods[]; .status.phase == "Succeeded"
      or (.status.phase == "Running"
          and any(.status.conditions[]?; .type == "Ready" and .status == "True")))
  and all(.items[] | select(.kind == "Deployment");
      (.status.availableReplicas // 0) >= .spec.replicas)
  and all(.items[] | select(.kind == "DaemonSet");
      (.status.desiredNumberScheduled // 0) > 0
      and (.status.numberReady // 0) >= .status.desiredNumberScheduled)'

cluster_ready() {
  local json
  json=$(kube get nodes -o json 2>/dev/null) || return 1
  printf '%s' "$json" | jq -e 'all(.items[]; any(.status.conditions[]?; .type == "Ready" and .status == "True"))' >/dev/null || return 1
  json=$(kube get pods,deployments,daemonsets -n kube-system -o json 2>/dev/null) || return 1
  printf '%s' "$json" | jq -e "$KUBE_SYSTEM_READY" >/dev/null || return 1
  json=$(kube get pods,deployments -n local-path-storage -o json 2>/dev/null) || return 1
  printf '%s' "$json" | jq -e "$KUBE_SYSTEM_READY" >/dev/null
}

cluster_exists() { kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; }

create_cluster() {
  kind create cluster --name "$CLUSTER" --image "$KIND_IMAGE" --kubeconfig "$KUBECONFIG"
}

delete_cluster() { kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG"; }

# --- Records ----------------------------------------------------------------------

record_load() {
  local opt=$1 phase=$2 loadavg total
  loadavg=$(uptime | sed -e 's/.*load average[s]*: //' -e 's/,//g')
  total=$(docker ps -q | wc -l | tr -d ' ')
  tsv load.tsv "$(utc_now)" "$opt" "$phase" "$loadavg" "$total" \
    "$(kind get clusters 2>/dev/null | paste -sd, - || true)"
}

to_mib_awk='function to_mib(v,  n, u) {
  n = v; sub(/[A-Za-z]+$/, "", n); u = v; sub(/^[0-9.]+/, "", u)
  if (u == "B") return n / 1048576
  if (u == "KiB" || u == "kB") return n / 1024
  if (u == "MiB" || u == "MB") return n
  if (u == "GiB" || u == "GB") return n * 1024
  return -1 }'

# One sample: memory working set and CPU of every pod of the layer (namespace
# of the provider, client pod excluded), from the kubelet Summary API, plus
# the whole node container from docker stats. Prints
# "layer_mem_mib<TAB>layer_cpu_pct<TAB>node_mem_mib<TAB>node_cpu_pct".
idle_sample() {
  local opt=$1 run=$2 sample=$3 summary pods node_stats
  summary=$(kube get --raw "/api/v1/nodes/$NODE/proxy/stats/summary") || die "summary API unreachable"
  pods=$(printf '%s' "$summary" | jq -r --arg ns "$NS_IDP" '
    .pods[] | select(.podRef.namespace == $ns)
    | select(.podRef.name | startswith("client-") | not)
    | [.podRef.namespace, .podRef.name, ((.memory.workingSetBytes // 0) / 1048576),
       ((.cpu.usageNanoCores // 0) / 10000000)] | @tsv')
  printf '%s\n' "$pods" | awk -F'\t' -v o="$opt" -v r="$run" -v s="$sample" \
    'NF == 4 { printf "%s\t%s\t%s\t%s\t%s\t%.1f\t%.2f\n", o, r, s, $1, $2, $3, $4 }' \
    >>"$TRIAL_DIR/idle-pods.tsv"
  node_stats=$(docker stats --no-stream --format '{{.CPUPerc}}\t{{.MemUsage}}' "$NODE" |
    awk -F'\t' "$to_mib_awk"'{ cpu = $1; sub(/%/, "", cpu); split($2, m, " "); printf "%.1f\t%.2f", to_mib(m[1]), cpu }')
  printf '%s\n' "$pods" | awk -F'\t' -v node="$node_stats" \
    'NF == 4 { m += $3; c += $4 } END { printf "%.1f\t%.2f\t%s\n", m, c, node }'
}

record_pulls() {
  local opt=$1 run=$2
  kube get events -A -o json | jq -r '.items[] | select(.reason == "Pulled") | .message' |
    sed -n -e 's/^Successfully pulled image "\([^"]*\)" in \([^ ]*\) .*/pulled|\1|\2/p' \
      -e 's/^Container image "\([^"]*\)" already present.*/present|\1|-/p' |
    sort -u | while IFS='|' read -r status image took; do
      tsv node-images.tsv "$opt" "$run" "$status" "$image" "$took"
    done
}

restarts() {
  kube get pods -n "$NS_IDP" -o json |
    jq '[.items[] | select(.metadata.name | startswith("client-") | not) | .status.containerStatuses[]?.restartCount] | add // 0'
}

registry_sizes() {
  docker manifest inspect -v "$1" 2>/dev/null | jq -r '
    [if type == "array" then .[] else . end
     | select((.Descriptor.platform.os // "linux") == "linux")
     | (.SchemaV2Manifest // .OCIManifest) as $m
     | "\(.Descriptor.platform.architecture)=\(([$m.layers[]?.size] | add) + ($m.config.size // 0))"]
    | map(select(startswith("arm64=") or startswith("amd64="))) | join(",")' 2>/dev/null || true
}

record_image() {
  local opt=$1 ref=$2 sizes try
  sizes=""
  for try in 1 2; do
    sizes=$(registry_sizes "${ref%%:*}@${ref#*@}")
    [ -z "$sizes" ] || break
    log "$opt: no size for $ref (try $try)"
    sleep 5
  done
  tsv images.tsv "$opt" "$ref" "${sizes:--}"
}

record_images() {
  local opt ref
  for opt in $OPTIONS; do
    for ref in $(option_images "$opt"); do record_image "$opt" "$ref"; done
  done
  record_image base "$PG_IMAGE"
  record_image base "$CLIENT_IMAGE"
}

# --- One run --------------------------------------------------------------------

# The wall clock must not jump while the run waits: a host that went to sleep
# would leave a stale cluster and meaningless timings. Fails instead.
sample_idle() {
  local opt=$1 run=$2 i sample samples="" t_wait
  t_wait=$(date +%s)
  sleep "$IDLE_WAIT"
  if [ $(($(date +%s) - t_wait)) -gt $((IDLE_WAIT + MAX_CLOCK_DRIFT)) ]; then
    log "$opt run $run: the clock jumped while waiting (host asleep?)"
    return 1
  fi
  for i in $(seq 1 "$SAMPLES"); do
    sample=$(idle_sample "$opt" "$run" "$i") || return 1
    samples="$samples$sample"$'\n'
    if [ "$i" -lt "$SAMPLES" ]; then sleep "$SAMPLE_GAP"; fi
  done
  printf '%s\t%s\t%s\t%s' \
    "$(printf '%s' "$samples" | cut -f1 | grep . | median_range | cut -f1)" \
    "$(printf '%s' "$samples" | cut -f2 | grep . | median_range | cut -f1)" \
    "$(printf '%s' "$samples" | cut -f3 | grep . | median_range | cut -f1)" \
    "$(printf '%s' "$samples" | cut -f4 | grep . | median_range | cut -f1)"
}

pat_ready() { kube get secret iam-admin-pat -n "$NS_IDP" >/dev/null 2>&1; }

idp_pods_replaced() {
  local before=$1 after
  after=$(kube get pods -n "$NS_IDP" -l "$(idp_pod_selector "$HTTP_OPT")" -o jsonpath='{.items[*].metadata.uid}' 2>/dev/null)
  [ -n "$after" ] && [ "$after" != "$before" ]
}

# macOS only: true if the power log shows the host entering sleep since SINCE
# (local time, "YYYY-MM-DD HH:MM:SS", the format of the log). A closed lid on
# battery sleeps the host whatever caffeinate asserts; such a run is void.
host_slept_since() {
  command -v pmset >/dev/null || return 1
  pmset -g log 2>/dev/null | awk -v s="$1" 'substr($0, 1, 19) >= s && /Entering Sleep/ { found = 1 } END { exit !found }'
}

timed_run() {
  local opt=$1 run=$2 log_file started t_create t_cluster t0 t_ready ready_s="-" idle restarts_n
  local back_s="-" uids admin="-" since_local
  log_file="$LOGS/$opt-run-$run.log"
  since_local=$(date "+%Y-%m-%d %H:%M:%S")
  HTTP_OPT=$opt
  ZI_UID=""
  record_load "$opt" "run-$run"
  started=$(utc_now)
  log "$opt run $run: create cluster"
  t_create=$(now)
  create_cluster >"$log_file" 2>&1 || die "$opt run $run: kind create failed, see $log_file"
  t_cluster=$(wait_streak "$CLUSTER_TIMEOUT" cluster_ready) || die "$opt run $run: cluster not ready"
  start_base "$log_file"

  if [ "$opt" != none ]; then
    prepare_database "$opt" >>"$log_file" 2>&1 || die "$opt run $run: database preparation failed"
    prepare_secrets "$opt" >>"$log_file" 2>&1 || die "$opt run $run: secrets failed"
  fi
  start_client "$log_file"

  if [ "$opt" = none ]; then
    kube scale deployment client -n "$NS_IDP" --replicas=0 >>"$log_file" 2>&1
    idle=$(sample_idle "$opt" "$run") || die "$opt run $run: sampling at rest failed"
    if host_slept_since "$since_local"; then die "$opt run $run: the host went to sleep during the run"; fi
    tsv runs.tsv "$opt" "$run" "$started" "$(seconds_between "$t_create" "$t_cluster")" \
      - "$idle" - - - 0
    log "$opt run $run: node at rest $(printf '%s' "$idle" | cut -f3) MiB"
    delete_cluster >>"$log_file" 2>&1 || die "$opt run $run: delete failed"
    return 0
  fi

  log "$opt run $run: install $(option_version "$opt")"
  t0=$(now)
  apply_layer "$opt" >>"$log_file" 2>&1 || die "$opt run $run: apply failed, see $log_file"
  if ! t_ready=$(wait_streak "$READY_TIMEOUT" discovery_ok); then
    kube get pods -A -o wide >>"$log_file" 2>&1 || true
    kube get events -A --field-selector type=Warning >>"$log_file" 2>&1 || true
    die "$opt run $run: not ready after ${READY_TIMEOUT}s, see $log_file"
  fi
  ready_s=$(seconds_between "$t0" "$t_ready")
  log "$opt run $run: ready in $ready_s s"

  if [ "$opt" = zitadel ]; then
    wait_until "$SECRET_TIMEOUT" pat_ready || log "$opt run $run: no PAT Secret after ${SECRET_TIMEOUT}s"
  fi
  oidc_check "$opt" ready "$run"
  admin=$(admin_check "$opt" "$run")

  # At rest, without the client pod.
  kube scale deployment client -n "$NS_IDP" --replicas=0 >>"$log_file" 2>&1
  idle=$(sample_idle "$opt" "$run") || die "$opt run $run: sampling at rest failed"
  restarts_n=$(restarts)
  kube scale deployment client -n "$NS_IDP" --replicas=1 >>"$log_file" 2>&1
  wait_until 120 client_ready || die "$opt run $run: client pod not back"

  # M7: the provider pod is deleted, cluster kept.
  uids=$(kube get pods -n "$NS_IDP" -l "$(idp_pod_selector "$opt")" -o jsonpath='{.items[*].metadata.uid}')
  t0=$(now)
  kube delete pods -n "$NS_IDP" -l "$(idp_pod_selector "$opt")" --wait=false >>"$log_file" 2>&1
  wait_until 120 idp_pods_replaced "$uids" || log "$opt run $run: provider pod not replaced within 120 s"
  if t_ready=$(wait_streak "$READY_TIMEOUT" discovery_ok); then
    back_s=$(seconds_between "$t0" "$t_ready")
  fi
  log "$opt run $run: ready again after $back_s s"
  oidc_check "$opt" pod-deleted "$run"

  if host_slept_since "$since_local"; then die "$opt run $run: the host went to sleep during the run"; fi
  record_pulls "$opt" "$run"
  tsv runs.tsv "$opt" "$run" "$started" "$(seconds_between "$t_create" "$t_cluster")" \
    "$ready_s" "$idle" "$back_s" "$admin" "$restarts_n"
  if [ "$KEEP_CLUSTER" = 1 ] && [ "$run" = "$RUNS" ]; then
    log "$opt run $run: cluster kept (KEEP_CLUSTER=1), KUBECONFIG=$KUBECONFIG"
    return 0
  fi
  log "$opt run $run: delete cluster"
  delete_cluster >>"$log_file" 2>&1 || die "$opt run $run: delete failed"
}

# --- Start-up checks --------------------------------------------------------------

check_versions() {
  local v
  for v in docker kind kubectl gh jq gdate openssl xxd shasum awk; do
    command -v "$v" >/dev/null || die "$v not found"
  done
  v=$(kind version | awk '{ print $2 }')
  [ "$v" = "$KIND_VERSION" ] || die "kind $v found, $KIND_VERSION expected"
  tsv versions.tsv kind "$v"
  v=$(kubectl version --client -o json | jq -r '.clientVersion.minor' | tr -dc '0-9')
  case " $KUBECTL_MINORS " in
    *" $v "*) ;;
    *) die "kubectl 1.$v is more than one minor away from the node image" ;;
  esac
  tsv versions.tsv kubectl "$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion')"
  tsv versions.tsv node-image "$KIND_IMAGE"
  tsv versions.tsv postgres "$PG_IMAGE"
  tsv versions.tsv client "$CLIENT_IMAGE"
  tsv versions.tsv openssl "$(openssl version)"
  tsv versions.tsv docker "$(docker version --format '{{.Server.Version}}')"
  tsv versions.tsv engine "$(docker info --format '{{.OperatingSystem}} {{.Architecture}} {{.NCPU}} CPU {{.MemTotal}} B cgroup v{{.CgroupVersion}}')"
  tsv versions.tsv host "$(sysctl -n hw.model 2>/dev/null || uname -m) $(sw_vers -productVersion 2>/dev/null || uname -r)"
  tsv versions.tsv power "$(pmset -g batt 2>/dev/null | head -n 1 || echo -)"
  for v in $OPTIONS; do
    case $v in
      keycloak | zitadel | none) tsv versions.tsv "$v" "$(option_version "$v")" ;;
      *) die "unknown option: $v" ;;
    esac
  done
}

acquire_lock() {
  [ -n "$BENCH_LOCK" ] || return 0
  if ! mkdir "$BENCH_LOCK" 2>/dev/null; then
    echo "lock $BENCH_LOCK is held: $(cat "$BENCH_LOCK/owner" 2>/dev/null || echo unknown owner)" >&2
    exit 75
  fi
  LOCK_HELD=1
  printf 'BENCH-012 %s\n' "$(utc_now)" >"$BENCH_LOCK/owner"
}

release_lock() {
  if [ "$LOCK_HELD" = 1 ]; then
    rm -f "$BENCH_LOCK/owner"
    rmdir "$BENCH_LOCK" 2>/dev/null || log "lock $BENCH_LOCK not empty, left in place"
    LOCK_HELD=0
  fi
}

# --- Cleanup ----------------------------------------------------------------------

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  set +e
  if cluster_exists && { [ "$KEEP_CLUSTER" != 1 ] || [ "$rc" != 0 ]; }; then
    log "cleanup: deleting the kind cluster $CLUSTER"
    delete_cluster >>"$LOGS/cleanup.log" 2>&1
  fi
  if ! cluster_exists && [ "$KIND_NETWORK_EXISTED" = 0 ] && docker network inspect kind >/dev/null 2>&1 &&
    [ "$(docker network inspect kind --format '{{len .Containers}}')" = 0 ]; then
    log "cleanup: removing the kind network created by this run"
    docker network rm kind >>"$LOGS/cleanup.log" 2>&1
  fi
  release_lock
  log "results in $TRIAL_DIR"
  exit "$rc"
}

# --- Summary ----------------------------------------------------------------------

summarize() {
  local opt column name values
  tsv summary.tsv option metric runs values median range
  for opt in $OPTIONS; do
    for column in 4:cluster_s 5:ready_s 6:layer_mem_mib 7:layer_cpu_pct 8:node_mem_mib 9:node_cpu_pct 10:back_s; do
      name=${column#*:}
      values=$(awk -F'\t' -v o="$opt" -v c="${column%%:*}" \
        '$1 == o && $2 != "run" && $c ~ /^[0-9.]+$/ { print $c }' "$TRIAL_DIR/runs.tsv")
      tsv summary.tsv "$opt" "$name" "$(printf '%s\n' "$values" | grep -c . || true)" \
        "$(printf '%s\n' "$values" | paste -sd, -)" "$(printf '%s\n' "$values" | grep . | median_range)"
    done
  done
}

# --- Main -------------------------------------------------------------------------

main() {
  local opt run
  if [ $# -gt 0 ]; then
    TRIAL_DIR=$1
    if [ -e "$TRIAL_DIR" ] && [ -n "$(ls -A "$TRIAL_DIR")" ]; then
      echo "TRIAL_DIR must be missing or empty: $TRIAL_DIR" >&2
      exit 2
    fi
    mkdir -p "$TRIAL_DIR"
  else
    TRIAL_DIR=$(mktemp -d)
  fi
  TRIAL_DIR=$(cd "$TRIAL_DIR" && pwd)
  LOGS="$TRIAL_DIR/logs"
  mkdir -p "$LOGS"
  export KUBECONFIG="$TRIAL_DIR/kubeconfig"
  : >"$KUBECONFIG"
  chmod 600 "$KUBECONFIG"

  tsv versions.tsv item version
  tsv files.tsv kind file sha256
  tsv images.tsv option image compressed_bytes
  tsv runs.tsv option run started_utc cluster_s ready_s layer_mem_mib layer_cpu_pct \
    node_mem_mib node_cpu_pct back_s admin_refused admin_secret_ok restarts
  tsv idle-pods.tsv option run sample namespace pod mem_mib cpu_pct
  tsv node-images.tsv option run status image took
  tsv oidc.tsv option run step token_status issuer signature_ok alg kid issuer_ok exp_ok claims
  tsv admin.tsv option run attempt status
  tsv load.tsv utc option phase loadavg_1_5_15 running_containers kind_clusters

  # Start-up checks first, without any trap: a refusal deletes nothing.
  check_versions
  cluster_exists && die "a kind cluster named $CLUSTER already exists"
  if docker network inspect kind >/dev/null 2>&1; then KIND_NETWORK_EXISTED=1; fi
  acquire_lock
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  log "trial directory: $TRIAL_DIR"

  check_files
  record_images

  run=1
  while [ "$run" -le "$RUNS" ]; do
    for opt in $OPTIONS; do
      timed_run "$opt" "$run"
      sleep "$PAUSE_BETWEEN_RUNS"
    done
    run=$((run + 1))
  done
  summarize
  column -t -s "$(printf '\t')" "$TRIAL_DIR/summary.tsv" >&2 || true
}

main "$@"
