#!/usr/bin/env bash
# The application layer of the local cluster (spec 001, plan, "Ce que fait
# task up", points 7 and 8; contracts/task-cli.md).
#
# Usage: bash local/scripts/app.sh check | up
#   check  the files of the composition are there; calls no kubectl and
#          creates nothing: task up runs it before it creates the cluster
#   up     applies local/k8s/lite server-side (kubectl apply -k): the local
#          environment of the common layer, namespace, Gateway and
#          HTTPRoutes, with the component of the local target, Postgres for
#          now (research RS-01). Then waits until the database answers an
#          authenticated SELECT 1, with the user of db-auth, through its
#          Service (ADR-012, condition 6).
#
# Step 9 adds the build and the load of the API and the front, defined once
# here (ADR-006, condition 6), and the rest of "ready". The Secrets come
# before, from local/scripts/secrets.sh. The SELECT 1 runs in the container
# of Postgres, which mounts db-auth: the password goes from its file to the
# environment of psql inside the pod, and never through this machine. Every
# kubectl call goes through kube of lib/local-env.sh (S19). Nothing here
# creates or removes a container, a network or a volume of the engine.
set -euo pipefail

here="${BASH_SOURCE[0]}"
case "$here" in
  */*) here="${here%/*}" ;;
  *) here="." ;;
esac
# shellcheck disable=SC1091 # lib/local-env.sh is checked on its own
. "$here/lib/local-env.sh"
root="$(CDPATH='' cd -- "$here/../.." && pwd)"

# The one profile delivered until step 12 (tasks.md, gap 14).
readonly COMPOSITION="$root/local/k8s/lite"
readonly DATABASE_STATEFULSET="postgres"
readonly DATABASE_POD="postgres-0"
readonly DATABASE_CONTAINER="postgres"
readonly DATABASE_SERVICE="postgres"
readonly DATABASE_NAME="app"
# How long the database gets to be ready: the node pulls its image through
# the mirror, from Docker Hub on a new mirror volume (168.5 MB in amd64,
# ADR-012), then initializes the volume; Postgres was ready in 8.9 s with
# the image in cache in BENCH-011 (ADR-012).
readonly ROLLOUT_WAIT="300s"
# Then how long the authenticated SELECT 1 may keep failing, and the pause
# between two tries.
readonly QUERY_SECONDS=60
readonly QUERY_PAUSE_SECONDS=2

die() {
  printf 'app: %s\n' "$1" >&2
  exit 1
}

check() {
  local file
  for file in local/k8s/lite/kustomization.yaml local/k8s/component/kustomization.yaml \
    local/data/kustomization.yaml local/data/statefulset.yaml local/data/service.yaml \
    local/data/init/10-app-role.sh; do
    [ -f "$root/$file" ] || die "$file is missing. Restore it from the repository. Nothing was applied."
  done
}

# select_one: SELECT 1 as the user of db-auth, on the database app, through
# the Service, from inside the container of Postgres. The script below is
# run by bash in the pod: its $(...) read the files of db-auth there.
select_one() {
  # shellcheck disable=SC2016 # expanded by bash in the pod, not here
  kube --namespace "$APP_NAMESPACE" exec "$DATABASE_POD" --container "$DATABASE_CONTAINER" -- \
    bash -c 'PGPASSWORD="$(cat /run/secrets/db-auth/password)" exec psql --host="$1" --port=5432 --username="$(cat /run/secrets/db-auth/username)" --dbname="$2" --no-password --no-psqlrc --tuples-only --no-align --command="SELECT 1"' \
    select-one "$DATABASE_SERVICE" "$DATABASE_NAME" 2>/dev/null
}

up() {
  local answer waited=0
  check
  kube apply --server-side -k "$COMPOSITION" >/dev/null ||
    die "local/k8s/lite was not applied; the messages of kubectl are above."
  printf 'Application: local/k8s/lite applied in %s.\n' "$APP_NAMESPACE"
  if ! kube --namespace "$APP_NAMESPACE" rollout status "statefulset/$DATABASE_STATEFULSET" \
    --timeout="$ROLLOUT_WAIT" >/dev/null; then
    die "the database is not ready within $ROLLOUT_WAIT. Look at its pod: kubectl --kubeconfig $KUBECONFIG_FILE --context $KUBE_CONTEXT --namespace $APP_NAMESPACE describe pod $DATABASE_POD."
  fi
  while :; do
    answer="$(select_one)" || answer=""
    [ "$answer" = 1 ] && break
    [ "$waited" -lt "$QUERY_SECONDS" ] ||
      die "the database does not answer an authenticated SELECT 1 through its Service within $QUERY_SECONDS s. Look at its log: kubectl --kubeconfig $KUBECONFIG_FILE --context $KUBE_CONTEXT --namespace $APP_NAMESPACE logs $DATABASE_POD."
    sleep "$QUERY_PAUSE_SECONDS"
    waited=$((waited + QUERY_PAUSE_SECONDS))
  done
  printf 'Database: ready, SELECT 1 answered by the user of db-auth through the Service %s.\n' "$DATABASE_SERVICE"
}

case "${1:-}" in
  check) check ;;
  up) up ;;
  *) die "usage: bash local/scripts/app.sh check | up" ;;
esac
