#!/usr/bin/env bash
# control: E05
# carries: FR-004; ADR-006, condition 1; ADR-007, conditions 1 and 5; ADR-012, condition 3
#
# A second task up on an environment that exists keeps the Secrets and the
# data (récit 2, scénario 3; ADR-012, condition 3):
# - the SHA-256 of each value of db-auth and db-superuser is the same after
#   the second task up as before it;
# - no Secret carries the annotation
#   kubectl.kubernetes.io/last-applied-configuration, the trace of a
#   kubectl apply (ADR-007, condition 1);
# - each Secret is of type kubernetes.io/basic-auth with the keys password
#   and username and no other (contracts/secrets.md; ADR-007, condition 5),
#   and the username of db-auth is app;
# - a row written before the second task up, as the user of db-auth, is
#   read after it.
# Only fingerprints of the values are kept and compared; none is printed.
# The go-templates of kubectl hold their own variables ($k, $v).
# shellcheck disable=SC2016
set -uo pipefail
# shellcheck disable=SC1091 # lib/e2e.sh is checked on its own
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/e2e.sh"

readonly PROBE_TABLE="e2e_probe_e05"

# fingerprints: "<secret> <key> <sha256>" for each key of each Secret.
fingerprints() {
  local secret key
  for secret in $E2E_SECRETS; do
    for key in $E2E_SECRET_KEYS; do
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

for secret in $E2E_SECRETS; do
  annotations="$(kube_e2e -n "$E2E_APP_NAMESPACE" get secret "$secret" --output 'go-template={{range $k, $v := .metadata.annotations}}{{$k}} {{end}}')"
  case " $annotations" in
    *" kubectl.kubernetes.io/last-applied-configuration "*) fail "the Secret $secret carries the annotation last-applied-configuration: it went through kubectl apply" ;;
  esac
  type="$(kube_e2e -n "$E2E_APP_NAMESPACE" get secret "$secret" --output 'jsonpath={.type}')"
  [ "$type" = "$E2E_SECRET_TYPE" ] || fail "the Secret $secret is of type $type, $E2E_SECRET_TYPE expected"
  keys="$(kube_e2e -n "$E2E_APP_NAMESPACE" get secret "$secret" --output 'go-template={{range $k, $v := .data}}{{$k}} {{end}}')"
  [ "$keys" = "$E2E_SECRET_KEYS " ] || fail "the Secret $secret has the keys \"$keys\", exactly \"$E2E_SECRET_KEYS\" expected"
done
username="$(secret_value db-auth username)"
[ "$username" = "$E2E_APP_USER" ] || fail "the username of db-auth is \"$username\", $E2E_APP_USER expected"

read_back="$(db_query db-auth app "SELECT mark FROM $PROBE_TABLE WHERE mark = '$mark'" 2>&1)" || read_back=""
[ "$read_back" = "$mark" ] || fail "the row written before the second task up is not read after it (got \"$read_back\")"
db_query db-auth app "DROP TABLE IF EXISTS $PROBE_TABLE" >/dev/null || printf 'E05: could not drop the table %s.\n' "$PROBE_TABLE"

e2e_finish
