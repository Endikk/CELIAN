#!/usr/bin/env bash
# E13: the cache refuses a command without authentication, and runs as
# ADR-015 wants it, on the environment that task up left (spec 001, plan,
# matrix E13; ADR-006, condition 2; ADR-015, conditions 4 to 6, 10, 16 and
# 17; research RS-11):
# - condition 4: PING without the password gets NOAUTH; with it, the
#   commands that Memorystore blocks, and @scripting, get NOPERM, and the
#   commands that the API client sends do not; cache.conf holds the SHA-256
#   of the password, never the password;
# - condition 5 (M6 of BENCH-014): the password is in no command line and
#   no environment of the processes of the cache container;
# - condition 6: a pod that the NetworkPolicy does not admit cannot reach
#   6379, while it reaches another pod; the cache pod opens no connection;
# - condition 10: 100 MiB written into a cache of maxmemory 64mb evict keys,
#   and the container never restarts;
# - condition 16 (M8): INFO passes the ACL, and valkey_version is on the
#   cache_engine_line of platform.yaml.
#
# Two pods of the test, removed at the end, with the image of the cache, so
# that nothing else is pulled: e13-client, a client that the NetworkPolicy
# admits (label cache-probe), which reads the password from cache-auth by
# secretKeyRef and by a mounted file; e13-outsider, which the NetworkPolicy
# does not admit, and which serves a password-less server on port 7000 for
# the counter-checks. The password never reaches the machine: the checks
# that need it run inside e13-client, the Secret file as grep pattern, and
# what crosses the machine is the content of /proc and of cache.conf, which
# must not hold it. The client never sends AUTH to the outsider.
set -uo pipefail

# shellcheck disable=SC1091 # lib/e2e.sh is checked on its own
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/e2e.sh"

ns="$E2E_APP_NAMESPACE"
client="e13-client"
outsider="e13-outsider"
secret_file="/run/secrets/cache-auth/password"
# The settings of the init container (local/data/cache/init/write-config.sh).
maxmemory_bytes=67108864
fill_keys=100
fill_offset=1048575

cleanup() {
  kube_e2e --namespace "$ns" delete pod "$client" "$outsider" --ignore-not-found --wait=false >/dev/null 2>&1 || :
}
trap cleanup EXIT

kube_ns() {
  kube_e2e --namespace "$ns" "$@"
}

# The commands of the test pods. The client idles; the outsider serves a
# server without password or persistence on port 7000.
client_command='["sh", "-c", "trap '"'"'exit 0'"'"' TERM; while :; do sleep 1; done"]'
outsider_command='["valkey-server", "--port", "7000", "--save", "", "--appendonly", "no", "--protected-mode", "no"]'

# test_pod NAME LABEL COMMAND [secret]: the manifest of a test pod, under the
# restricted profile, on the standard output.
test_pod() {
  printf 'apiVersion: v1\nkind: Pod\nmetadata:\n  name: %s\n  labels:\n    app.kubernetes.io/name: %s\n' "$1" "$2"
  printf 'spec:\n  automountServiceAccountToken: false\n  enableServiceLinks: false\n  terminationGracePeriodSeconds: 1\n'
  printf '  securityContext:\n    runAsNonRoot: true\n    runAsUser: 999\n    runAsGroup: 1000\n    fsGroup: 1000\n    seccompProfile:\n      type: RuntimeDefault\n'
  printf '  containers:\n    - name: main\n      image: %s\n      command: %s\n' "$image" "$3"
  printf '      securityContext:\n        allowPrivilegeEscalation: false\n        readOnlyRootFilesystem: true\n        capabilities:\n          drop: [ALL]\n'
  printf '      volumeMounts:\n        - name: data\n          mountPath: /data\n'
  if [ "${4:-}" = secret ]; then
    printf '        - name: cache-auth\n          mountPath: /run/secrets/cache-auth\n          readOnly: true\n'
    printf '      env:\n        - name: VALKEYCLI_AUTH\n          valueFrom:\n            secretKeyRef:\n              name: cache-auth\n              key: password\n'
  fi
  printf '  volumes:\n    - name: data\n      emptyDir:\n        sizeLimit: 8Mi\n'
  if [ "${4:-}" = secret ]; then
    printf '    - name: cache-auth\n      secret:\n        secretName: cache-auth\n        defaultMode: 0440\n'
  fi
}

# client_cli ARG...: valkey-cli from the client, through the Service,
# authenticated by VALKEYCLI_AUTH.
client_cli() {
  kube_ns exec "$client" -- valkey-cli -t 5 -h cache -p 6379 "$@" 2>&1
}

# anonymous HOST PORT ARG...: valkey-cli from the client without any
# password.
anonymous() {
  # shellcheck disable=SC2016 # expanded by the shell of the pod
  kube_ns exec "$client" -- sh -c 'unset VALKEYCLI_AUTH REDISCLI_AUTH; exec valkey-cli -t 5 "$@"' sh "$@" 2>&1
}

# count_password: reads text on the standard input, and prints how many of
# its lines hold the password of cache-auth, counted inside the client.
count_password() {
  kube_ns exec -i "$client" -- sh -c '[ -s '"$secret_file"' ] || { echo err; exit 0; }; tr "\000" "\n" | grep -c -F -f '"$secret_file"' || true' 2>&1 | tr -d '[:space:]'
}

# --- The cache that task up left ----------------------------------------------

if ! kube_ns rollout status deployment/cache --timeout=120s >/dev/null 2>&1; then
  fail "the Deployment cache is not available in $ns: task up applies the cache layer and creates cache-auth (spec 001, T078 and T079; ADR-015)"
  e2e_finish
fi
image="$(kube_ns get deployment cache --output 'jsonpath={.spec.template.spec.containers[?(@.name=="cache")].image}')"
if [ -z "$image" ]; then
  fail "the Deployment cache has no container named cache"
  e2e_finish
fi

if ! { test_pod "$client" cache-probe "$client_command" secret | kube_ns create -f - >/dev/null &&
  test_pod "$outsider" e13-outsider "$outsider_command" | kube_ns create -f - >/dev/null; }; then
  fail "the test pods were not created; the messages of kubectl are above"
  e2e_finish
fi
if ! kube_ns wait --for=condition=Ready "pod/$client" "pod/$outsider" --timeout=120s >/dev/null; then
  fail "the test pods are not ready within 120 s"
  e2e_finish
fi

# --- Condition 4: authentication and ACL ------------------------------------

out="$(anonymous -h cache -p 6379 ping)"
case "$out" in
  *NOAUTH*) ;;
  *) fail "PING without the password must get NOAUTH (ADR-006, condition 2; ADR-015, condition 4), got: $out" ;;
esac

out="$(client_cli ping | tr -d '\r')"
[ "$out" = PONG ] || fail "an authenticated PING through the Service must get PONG (ADR-015, condition 17), got: $out"

# What Memorystore blocks, @admin and @scripting (research RS-11). DEBUG is
# also a protected command, refused before the ACL while
# enable-debug-command is no (src/server.c, processCommand, 9.1.4).
for command in "CONFIG GET maxmemory" "CONFIG SET maxmemory 1mb" "DEBUG SLEEP 0" "SAVE" "BGSAVE" \
  "ACL LIST" "ACL WHOAMI" "ACL CAT" "MODULE LIST" "SLOWLOG GET" "CLIENT LIST" "SWAPDB 0 1" \
  "MOVE e13:key 1" "MIGRATE 127.0.0.1 1 e13:key 0 100" "XSETID e13:stream 0-1" "LASTSAVE" \
  "EVAL return 0" "FUNCTION LIST" \
  "REPLICAOF 127.0.0.1 1" "SLAVEOF 127.0.0.1 1" "SHUTDOWN NOSAVE" "SYNC" "PSYNC e13 -1" "FAILOVER" \
  "BGREWRITEAOF" "CLIENT PAUSE 1" "CLIENT NO-EVICT on" "PFDEBUG GETREG e13:hll" \
  "MODULE LOAD /nonexistent.so" "SLOWLOG LEN"; do
  # shellcheck disable=SC2086 # the command splits into its words on purpose
  out="$(client_cli $command)"
  case "$out" in
    *NOPERM* | *"command not allowed"*) ;;
    *) fail "$command must be refused by the cache (ADR-015, condition 4), got: $out" ;;
  esac
done

# What the API client sends (research RS-11), and the commands of the
# example: none gets NOPERM.
for command in "HELLO 2" "CLIENT SETNAME e13" "CLIENT SETINFO LIB-NAME e13" "CLIENT ID" "ECHO e13" \
  "SELECT 0" "INFO server" "CLUSTER NODES" "SET e13:key value EX 60" "GET e13:key" "EXPIRE e13:key 60" "DEL e13:key"; do
  # shellcheck disable=SC2086 # the command splits into its words on purpose
  out="$(client_cli $command)"
  case "$out" in
    *NOPERM* | *NOAUTH*) fail "$command is refused by the ACL of the cache; the API client needs it (research RS-11), got: $out" ;;
  esac
done

conf="$(kube_ns exec deploy/cache -c cache -- cat /etc/cache/cache.conf 2>&1)"
if ! printf '%s\n' "$conf" | grep -Eq '^user default on #[0-9a-f]{64} '; then
  fail "cache.conf has no ACL line with the SHA-256 of the password (ADR-015, condition 4)"
fi
found="$(printf '%s\n' "$conf" | count_password)"
[ "$found" = 0 ] || fail "cache.conf holds the password of cache-auth (ADR-015, condition 4): $found line(s), or the client could not read the Secret"

# --- Condition 5: no password in the command lines and environments --------

# shellcheck disable=SC2016 # expanded by the shell of the pod
found="$(kube_ns exec deploy/cache -c cache -- sh -c 'cat /proc/[0-9]*/cmdline /proc/[0-9]*/environ 2>/dev/null' | count_password)"
[ "$found" = 0 ] || fail "the password of cache-auth is in a command line or an environment of the cache container (ADR-015, condition 5; M6): $found line(s), or the client could not read the Secret"

# --- Condition 16: the line served --------------------------------------------

line="$(awk '$1 == "cache_engine_line:" { gsub(/"/, "", $2); print $2; exit }' "$E2E_ROOT/platform.yaml")"
served="$(client_cli INFO server | tr -d '\r' | sed -n 's/^valkey_version://p')"
case "$served" in
  "$line".*) ;;
  *) fail "the cache serves valkey_version '$served'; platform.yaml says cache_engine_line '$line' (ADR-015, condition 16)" ;;
esac

# --- Condition 6: the NetworkPolicy --------------------------------------------

outsider_ip="$(kube_ns get pod "$outsider" --output 'jsonpath={.status.podIP}')"
out="$(anonymous -h "$outsider_ip" -p 7000 ping | tr -d '\r')"
[ "$out" = PONG ] || fail "the client cannot reach the outsider pod on port 7000, so the checks of the NetworkPolicy prove nothing, got: $out"

# shellcheck disable=SC2016 # expanded by the shell of the pod
out="$(kube_ns exec "$outsider" -- sh -c 'valkey-cli -t 5 -h cache -p 6379 ping 2>&1; echo "exit $?"' 2>&1)"
case "$out" in
  *PONG* | *NOAUTH*) fail "a pod that the NetworkPolicy does not admit reaches the cache on 6379 (ADR-015, condition 6), got: $out" ;;
esac

out="$(kube_ns exec deploy/cache -c cache -- valkey-cli -t 5 -h "$outsider_ip" -p 7000 ping 2>&1)"
case "$out" in
  *PONG*) fail "the cache pod opens a connection to another pod; the NetworkPolicy gives it no way out (ADR-015, condition 6)" ;;
esac

# --- Condition 10: maxmemory and eviction ----------------------------------------

# shellcheck disable=SC2016 # expanded by the shell of the pod
if ! kube_ns exec "$client" -- sh -c 'i=0; while [ "$i" -lt "$1" ]; do valkey-cli -h cache -p 6379 SETRANGE "e13:fill:$i" "$2" x >/dev/null || exit 1; i=$((i + 1)); done' sh "$fill_keys" "$fill_offset"; then
  fail "the client could not write $fill_keys values of 1 MiB into the cache"
fi
memory="$(client_cli INFO memory | tr -d '\r')"
printf '%s\n' "$memory" | grep -qx "maxmemory:$maxmemory_bytes" ||
  fail "the cache does not run with maxmemory 64mb (ADR-015, condition 10)"
printf '%s\n' "$memory" | grep -qx 'maxmemory_policy:allkeys-lru' ||
  fail "the cache does not run with maxmemory-policy allkeys-lru (ADR-015, condition 15)"
evicted="$(client_cli INFO stats | tr -d '\r' | sed -n 's/^evicted_keys://p')"
case "$evicted" in
  '' | 0 | *[!0-9]*) fail "100 MiB written into a cache of 64 MiB evicted no key (ADR-015, condition 10), evicted_keys: '$evicted'" ;;
esac
restarts="$(kube_ns get pods --selector app.kubernetes.io/name=cache --output 'jsonpath={.items[*].status.containerStatuses[*].restartCount}')"
[ "$restarts" = 0 ] || fail "the cache container restarted while full (ADR-015, condition 10), restart counts: '$restarts'"
client_cli FLUSHDB >/dev/null

e2e_finish
