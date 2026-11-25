#!/usr/bin/env bash
# control: E12
# carries: FR-017; ADR-012, conditions 1, 2, 5, 8 and 9; R-20, R-35
#
# Postgres of the local layer, as it runs after task up:
# - the rules that the server loaded (pg_hba_file_rules) all ask for
#   scram-sha-256: no trust, no password in clear, no peer (condition 2);
# - from a pod of another namespace, psql without a password is refused,
#   for the user of db-auth and for the superuser: fe_sendauth (condition 2);
# - the role of db-auth logs in without SUPERUSER, CREATEDB, CREATEROLE,
#   REPLICATION nor BYPASSRLS, and owns the database app (condition 8);
# - server_version_num has the major postgres_major of platform.yaml
#   (condition 5);
# - the pod of the database is Ready in the namespace of the application,
#   which enforces the restricted profile, and Pod Security refused no pod
#   there (conditions 1 and 9).
# The queries run in the container of Postgres, which mounts both Secrets;
# no password reaches this machine.
set -uo pipefail
# shellcheck disable=SC1091 # lib/e2e.sh is checked on its own
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/e2e.sh"

readonly CLIENT_NAMESPACE="e2e-e12-client"

must_succeed up || e2e_finish

# pg_hba, as the server loaded it.
rules="$(db_query db-superuser postgres "SELECT type || ' ' || array_to_string(database, ',') || ' ' || array_to_string(user_name, ',') || ' ' || coalesce(address, '-') || ' ' || auth_method FROM pg_hba_file_rules ORDER BY rule_number")" ||
  fail "could not read pg_hba_file_rules as the superuser"
if [ -z "$rules" ]; then
  fail "pg_hba_file_rules is empty"
fi
other="$(printf '%s\n' "$rules" | grep . | awk '$NF != "scram-sha-256"' || true)"
if [ -n "$other" ]; then
  fail "rules of pg_hba ask for another method than scram-sha-256: $(printf '%s' "$other" | tr '\n' ';')"
fi
printf 'note: %s rule(s) of pg_hba, all scram-sha-256.\n' "$(printf '%s\n' "$rules" | grep -c .)"

# The role of db-auth and its database.
role="$(db_query db-superuser postgres "SELECT rolcanlogin, rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolbypassrls FROM pg_roles WHERE rolname = '$E2E_APP_USER'")" || role=""
[ "$role" = "t|f|f|f|f|f" ] || fail "the role $E2E_APP_USER has the attributes \"$role\" (login|superuser|createdb|createrole|replication|bypassrls); t|f|f|f|f|f expected"
owner="$(db_query db-superuser postgres "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = 'app'")" || owner=""
[ "$owner" = "$E2E_APP_USER" ] || fail "the database app belongs to \"$owner\", $E2E_APP_USER expected"

# The major against platform.yaml.
major="$(awk -F'"' '$1 ~ /^postgres_major:/ { print $2; exit }' "$E2E_ROOT/platform.yaml")"
version="$(db_query db-auth app "SHOW server_version_num")" || version=""
case "$version" in
  "$major"[0-9][0-9][0-9][0-9]) printf 'note: server_version_num %s, major %s.\n' "$version" "$major" ;;
  *) fail "server_version_num is \"$version\", the major $major of platform.yaml expected" ;;
esac

# The restricted profile on the namespace of the application, and the pod.
pod_security="$(kube_e2e get namespace "$E2E_APP_NAMESPACE" --output 'jsonpath={.metadata.labels.pod-security\.kubernetes\.io/enforce}')"
[ "$pod_security" = restricted ] || fail "the namespace $E2E_APP_NAMESPACE enforces Pod Security \"$pod_security\", restricted expected"
ready="$(kube_e2e -n "$E2E_APP_NAMESPACE" get pod postgres-0 --output 'jsonpath={.status.conditions[?(@.type=="Ready")].status}')"
[ "$ready" = True ] || fail "the pod postgres-0 is not Ready (Ready=$ready)"
refused="$(kube_e2e -n "$E2E_APP_NAMESPACE" get events --field-selector reason=FailedCreate \
  --output 'jsonpath={range .items[*]}{.message}{"\n"}{end}' 2>/dev/null | grep -F 'violates PodSecurity' || true)"
[ -z "$refused" ] || fail "Pod Security refused a pod of $E2E_APP_NAMESPACE: $refused"

# From another namespace, without a password. $1 is the Service, by its
# name in the cluster; psql never prompts (-w).
# shellcheck disable=SC2016 # expanded by bash in the pod
client_script='for user in app postgres; do
  db=app; [ "$user" = postgres ] && db=postgres
  out="$(psql -w "host=$1 port=5432 user=$user dbname=$db sslmode=disable connect_timeout=5" -c "SELECT 1" 2>&1)"
  echo "$user: exit $? $out"
done'
trap 'remove_client_namespace "$CLIENT_NAMESPACE"' EXIT
if client_namespace "$CLIENT_NAMESPACE"; then
  client_pod "$CLIENT_NAMESPACE" no-password "set -- postgres.$E2E_APP_NAMESPACE.svc.cluster.local; $client_script"
  if [ "$STATUS" -ne 0 ]; then
    fail "the client pod of $CLIENT_NAMESPACE did not run to its end"
    show_output
  else
    for user in app postgres; do
      line="$(printf '%s\n' "$OUTPUT" | grep "^$user: " || true)"
      case "$line" in
        *"exit 0 "*) fail "psql as $user without a password, from $CLIENT_NAMESPACE, was accepted" ;;
        *"no password supplied"*) printf 'note: psql as %s without a password, from %s: refused (fe_sendauth).\n' "$user" "$CLIENT_NAMESPACE" ;;
        *) fail "psql as $user without a password, from $CLIENT_NAMESPACE, failed for another reason than the missing password: $line" ;;
      esac
    done
  fi
else
  fail "could not create the namespace $CLIENT_NAMESPACE of the client pod"
fi

e2e_finish
