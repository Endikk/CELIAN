#!/usr/bin/env bash
# control: E05
# carries: FR-004; ADR-006, condition 1; ADR-007, conditions 1 and 5; ADR-012, condition 3; ADR-015, condition 5; research RS-10
#
# A second task up on an environment that exists keeps the Secrets and the
# data (récit 2, scénario 3; ADR-012, condition 3):
# - the SHA-256 of each value of db-auth, db-superuser and cache-auth is the
#   same after the second task up as before it;
# - no Secret carries the annotation
#   kubectl.kubernetes.io/last-applied-configuration, the trace of a
#   kubectl apply (ADR-007, condition 1);
# - db-auth and db-superuser are of type kubernetes.io/basic-auth with the
#   keys password and username and no other, cache-auth is Opaque with the
#   key password alone (contracts/secrets.md; ADR-007, condition 5;
#   ADR-015, condition 5), and the username of db-auth is app;
# - gateway-tls is kept like the others: the SHA-256 of its tls.crt and of
#   its tls.key is the same after the second task up, so the certificate
#   served by the gateway does not change from one start to the next
#   (research RS-10); it is of type kubernetes.io/tls with the keys tls.crt
#   and tls.key and no other, and carries no last-applied-configuration;
# - a row written before the second task up, as the user of db-auth, is
#   read after it.
# Only fingerprints of the values are kept and compared; none is printed.
# The go-templates of kubectl hold their own variables ($k, $v).
# shellcheck disable=SC2016
set -uo pipefail
# shellcheck disable=SC1091 # lib/e2e.sh is checked on its own
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/e2e.sh"

readonly PROBE_TABLE="e2e_probe_e05"

# expected_keys SECRET / expected_type SECRET: the keys and the type that
# contracts/secrets.md gives the Secret; cache-auth has the key password
# alone and is Opaque.
expected_keys() {
  case "$1" in
    "$E2E_CACHE_SECRET") printf '%s' "$E2E_CACHE_SECRET_KEYS" ;;
    "$E2E_TLS_SECRET") printf '%s' "$E2E_TLS_SECRET_KEYS" ;;
    *) printf '%s' "$E2E_SECRET_KEYS" ;;
  esac
}
expected_type() {
  case "$1" in
    "$E2E_CACHE_SECRET") printf '%s' "$E2E_CACHE_SECRET_TYPE" ;;
    "$E2E_TLS_SECRET") printf '%s' "$E2E_TLS_SECRET_TYPE" ;;
    *) printf '%s' "$E2E_SECRET_TYPE" ;;
  esac
}

# fingerprints: "<secret> <key> <sha256>" for each key of each Secret.
fingerprints() {
  local secret key
  for secret in $E2E_KEPT_SECRETS; do
    for key in $(expected_keys "$secret"); do
      printf '%s %s %s\n' "$secret" "$key" "$(secret_value "$secret" "$key" | sha256_stdin)"
    done
  done
}

must_succeed up || e2e_finish
before="$(fingerprints)"
mark="e05-$(date +%s)"
if ! db_query db-auth app "CREATE TABLE IF NOT EXISTS $PROBE_TABLE (mark text); INSERT INTO $PROBE_TABLE VALUES ('$mark')" >/dev/null; then
  fail "could not write a row as the user of db-auth before the second task up"
fi

must_succeed up || e2e_finish
after="$(fingerprints)"
changed="$(printf '%s\n' "$before" | while read -r secret key sum; do
  printf '%s\n' "$after" | grep -qx "$secret $key $sum" || printf '%s.%s ' "$secret" "$key"
done)"
if [ -n "$changed" ]; then
  fail "values of the Secrets changed at the second task up: $changed"
fi

for secret in $E2E_KEPT_SECRETS; do
  want_type="$(expected_type "$secret")"
  want_keys="$(expected_keys "$secret")"
  annotations="$(kube_e2e -n "$E2E_APP_NAMESPACE" get secret "$secret" --output 'go-template={{range $k, $v := .metadata.annotations}}{{$k}} {{end}}')"
  case " $annotations" in
    *" kubectl.kubernetes.io/last-applied-configuration "*) fail "the Secret $secret carries the annotation last-applied-configuration: it went through kubectl apply" ;;
  esac
  type="$(kube_e2e -n "$E2E_APP_NAMESPACE" get secret "$secret" --output 'jsonpath={.type}')"
  [ "$type" = "$want_type" ] || fail "the Secret $secret is of type $type, $want_type expected"
  keys="$(kube_e2e -n "$E2E_APP_NAMESPACE" get secret "$secret" --output 'go-template={{range $k, $v := .data}}{{$k}} {{end}}')"
  [ "$keys" = "$want_keys " ] || fail "the Secret $secret has the keys \"$keys\", exactly \"$want_keys\" expected"
done
username="$(secret_value db-auth username)"
[ "$username" = "$E2E_APP_USER" ] || fail "the username of db-auth is \"$username\", $E2E_APP_USER expected"

read_back="$(db_query db-auth app "SELECT mark FROM $PROBE_TABLE WHERE mark = '$mark'" 2>&1)" || read_back=""
[ "$read_back" = "$mark" ] || fail "the row written before the second task up is not read after it (got \"$read_back\")"
db_query db-auth app "DROP TABLE IF EXISTS $PROBE_TABLE" >/dev/null || printf 'E05: could not drop the table %s.\n' "$PROBE_TABLE"

e2e_finish
