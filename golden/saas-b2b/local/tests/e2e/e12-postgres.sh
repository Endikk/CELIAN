#!/usr/bin/env bash
# control: E12
# carries: FR-017; ADR-012, conditions 1, 2, 5, 8 and 9; R-20, R-35
#
# Postgres of the local layer, as it runs after task up:
# - the rules that the server loaded (pg_hba_file_rules) all ask for
#   scram-sha-256: no trust, no password in clear, no peer (condition 2);
# - from a pod that the NetworkPolicy postgres admits (label
#   app.kubernetes.io/name: api), psql without a password is refused, for the
#   user of db-auth and for the superuser: fe_sendauth (condition 2); a pod
#   of the namespace without that label, and a pod of another namespace,
#   reach nothing on 5432 (tasks.md, gap 84);
# - the role of db-auth logs in without SUPERUSER, CREATEDB, CREATEROLE,
#   REPLICATION nor BYPASSRLS, and owns the database app (condition 8);
# - server_version_num has the major postgres_major of platform.yaml
#   (condition 5);
# - the pod of the database is Ready in the namespace of the application,
#   which enforces the restricted profile, and Pod Security refused no pod
#   there (conditions 1 and 9); so are the pods of the API and the front,
#   admitted by the same profile (T087).
# The queries run in the container of Postgres, which mounts both Secrets;
# no password reaches this machine.
# shellcheck disable=SC2034 # E2E_CLIENT_LABELS is read by client_pod of lib/e2e.sh
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
for app in api front; do
  ready="$(kube_e2e -n "$E2E_APP_NAMESPACE" get pods --selector "app.kubernetes.io/name=$app" \
    --output 'jsonpath={.items[*].status.conditions[?(@.type=="Ready")].status}')"
  [ "$ready" = True ] || fail "the pod of $app is not Ready in $E2E_APP_NAMESPACE (Ready=\"$ready\"): either there is no such pod, or Pod Security refused it, or it does not start"
done
refused="$(kube_e2e -n "$E2E_APP_NAMESPACE" get events --field-selector reason=FailedCreate \
  --output 'jsonpath={range .items[*]}{.message}{"\n"}{end}' 2>/dev/null | grep -F 'violates PodSecurity' || true)"
[ -z "$refused" ] || fail "Pod Security refused a pod of $E2E_APP_NAMESPACE: $refused"

# Who reaches port 5432 (tasks.md, gap 84): the NetworkPolicy postgres admits
# the pods of the API (label app.kubernetes.io/name: api) and Postgres
# itself, on TCP 5432, and no other. kind applies NetworkPolicy, and this
# part proves it: a pod that the policy admits reaches the server and is
# refused for the missing password (fe_sendauth); a pod of the same
# namespace without the label, and a pod of another namespace, even with the
# label, get no answer at all (psql connect_timeout). $1 is the Service by
# its name in the cluster; psql never prompts (-w).
# shellcheck disable=SC2016 # expanded by bash in the pod
client_script='for user in app postgres; do
  db=app; [ "$user" = postgres ] && db=postgres
  out="$(psql -w "host=$1 port=5432 user=$user dbname=$db sslmode=disable connect_timeout=5" -c "SELECT 1" 2>&1)"
  echo "$user: exit $? $out"
done'

policy="$(kube_e2e -n "$E2E_APP_NAMESPACE" get networkpolicy postgres --output 'jsonpath={.spec.policyTypes[*]}' 2>/dev/null)"
[ "$policy" = Ingress ] || fail "the NetworkPolicy postgres is missing or does not isolate Ingress (policyTypes: \"$policy\")"

trap 'remove_client_namespace "$CLIENT_NAMESPACE"' EXIT
service="postgres.$E2E_APP_NAMESPACE.svc.cluster.local"

# judge_admitted NAME: the pod got to the server and was refused for the
# missing password, for each user.
judge_admitted() {
  local user line
  for user in app postgres; do
    line="$(printf '%s\n' "$OUTPUT" | grep "^$user: " || true)"
    case "$line" in
      *"exit 0 "*) fail "psql as $user without a password, from $1, was accepted" ;;
      *"no password supplied"*) printf 'note: psql as %s without a password, from %s: refused (fe_sendauth).\n' "$user" "$1" ;;
      *) fail "psql as $user without a password, from $1, failed for another reason than the missing password: $line" ;;
    esac
  done
}

# judge_blocked NAME: the pod got no answer from the server, for each user.
judge_blocked() {
  local user line
  for user in app postgres; do
    line="$(printf '%s\n' "$OUTPUT" | grep "^$user: " || true)"
    case "$line" in
      *"no password supplied"* | *"exit 0 "*) fail "psql as $user, from $1, reached the server on 5432: the NetworkPolicy postgres does not hold" ;;
      *"timeout expired"*) printf 'note: psql as %s, from %s: no answer, the NetworkPolicy holds.\n' "$user" "$1" ;;
      *) fail "psql as $user, from $1, failed for another reason than a timeout: $line" ;;
    esac
  done
}

E2E_CLIENT_LABELS="app.kubernetes.io/name=api"
client_pod "$E2E_APP_NAMESPACE" e12-admitted "set -- $service; $client_script"
if [ "$STATUS" -ne 0 ]; then
  fail "the admitted client pod did not run to its end"
  show_output
else
  judge_admitted "a pod labelled app.kubernetes.io/name=api of $E2E_APP_NAMESPACE"
fi

E2E_CLIENT_LABELS="app.kubernetes.io/name=other"
client_pod "$E2E_APP_NAMESPACE" e12-unlabelled "set -- $service; $client_script"
if [ "$STATUS" -ne 0 ]; then
  fail "the unlabelled client pod did not run to its end"
  show_output
else
  judge_blocked "a pod of $E2E_APP_NAMESPACE with another label"
fi

E2E_CLIENT_LABELS="app.kubernetes.io/name=api"
if client_namespace "$CLIENT_NAMESPACE"; then
  client_pod "$CLIENT_NAMESPACE" other-namespace "set -- $service; $client_script"
  if [ "$STATUS" -ne 0 ]; then
    fail "the client pod of $CLIENT_NAMESPACE did not run to its end"
    show_output
  else
    judge_blocked "a pod labelled app.kubernetes.io/name=api of $CLIENT_NAMESPACE"
  fi
else
  fail "could not create the namespace $CLIENT_NAMESPACE of the client pod"
fi
unset E2E_CLIENT_LABELS

e2e_finish
