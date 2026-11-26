#!/usr/bin/env bash
# The Secrets of the database and of the cache on the local cluster (spec
# 001, plan, "Ce que fait task up", point 6; contracts/secrets.md; ADR-007,
# condition 1; ADR-012, conditions 3, 8 and 10; ADR-015, conditions 5, 18
# and 19).
#
# Usage: bash local/scripts/secrets.sh up
#   up  checks first, and creates nothing when the check fails: the volume
#       of the database never lives without both its Secrets. Then applies
#       the namespace of the application from k8s/base/namespace.yaml, and
#       creates db-auth (username app), db-superuser (username postgres) and
#       cache-auth (type Opaque, the key password alone), each only when it
#       is missing. A Secret that exists is kept as it is, with or without
#       a volume. The cache keeps nothing, so cache-auth needs no check of
#       a volume; but its init container writes the hash of the password
#       once per start, so a cache-auth created while the Deployment cache
#       runs restarts that Deployment.
#
# Each password is 40 alphanumeric characters drawn from /dev/urandom, which
# go through a pipe to kubectl create -f - and nowhere else: no kubectl
# apply, which copies the value into an annotation; no file, no variable,
# no argument, no heredoc; nothing printed (ADR-007, condition 1). The task
# that runs this script is silent (S04). Every kubectl call goes through
# kube of lib/local-env.sh, which names the kubeconfig of the project and its
# context (S19). Nothing here creates or removes a container, a network or a
# volume of the engine.
set -euo pipefail

here="${BASH_SOURCE[0]}"
case "$here" in
  */*) here="${here%/*}" ;;
  *) here="." ;;
esac
# shellcheck disable=SC1091 # lib/local-env.sh is checked on its own
. "$here/lib/local-env.sh"
root="$(CDPATH='' cd -- "$here/../.." && pwd)"

readonly NAMESPACE_FILE="$root/k8s/base/namespace.yaml"
# The PVC of the volume claim template data of the StatefulSet postgres
# (local/data/statefulset.yaml), its one replica.
readonly DATA_VOLUME="data-postgres-0"
# The two Secrets of the database (contracts/secrets.md) and their fixed
# user names: app for the application, postgres for the superuser, which
# the readiness probe of local/data/statefulset.yaml names too.
readonly APP_SECRET="db-auth"
readonly APP_USER="app"
readonly SUPERUSER_SECRET="db-superuser"
readonly SUPERUSER="postgres"
# The Secret of the cache (ADR-015, condition 5) and the Deployment that
# reads it, local/data/cache/deployment.yaml.
readonly CACHE_SECRET="cache-auth"
readonly CACHE_DEPLOYMENT="cache"
# The password: PASSWORD_LENGTH alphanumeric characters kept out of
# RANDOM_BYTES bytes of /dev/urandom, about a quarter of which are
# alphanumeric. Its base64 form in the Secret is PASSWORD_BASE64_LENGTH
# characters long, which up checks once the Secret is created.
readonly PASSWORD_LENGTH=40
readonly RANDOM_BYTES=4096
readonly PASSWORD_BASE64_LENGTH=56

die() {
  printf 'secrets: %s\n' "$1" >&2
  exit 1
}

# present KIND NAME: yes when the object exists (a namespace, or an object of
# the namespace of the application), no when it does not. Stops task up when
# kubectl cannot tell: a missing answer is never taken for a missing object.
present() {
  local found
  if [ "$1" = namespace ]; then
    found="$(kube get namespace "$2" --ignore-not-found --output name)" ||
      die "cannot read the namespace $2; the messages of kubectl are above. Nothing was created."
  else
    found="$(kube --namespace "$APP_NAMESPACE" get "$1" "$2" --ignore-not-found --output name)" ||
      die "cannot read the $1 $2 of $APP_NAMESPACE; the messages of kubectl are above. Nothing was created."
  fi
  if [ -n "$found" ]; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

# check: when the volume of the database exists, both its Secrets exist too
# (ADR-012, condition 3). The variables POSTGRES_* and the script of the
# role only act on an empty volume: a new password would not open the data.
check() {
  local state missing=""
  [ -f "$NAMESPACE_FILE" ] || die "k8s/base/namespace.yaml is missing. Restore it from the repository. Nothing was created."
  state="$(present namespace "$APP_NAMESPACE")"
  [ "$state" = yes ] || return 0
  state="$(present persistentvolumeclaim "$DATA_VOLUME")"
  [ "$state" = yes ] || return 0
  state="$(present secret "$APP_SECRET")"
  [ "$state" = yes ] || missing="$APP_SECRET"
  state="$(present secret "$SUPERUSER_SECRET")"
  [ "$state" = yes ] || missing="${missing:+$missing and }$SUPERUSER_SECRET"
  [ -z "$missing" ] && return 0
  die "the volume of the database, PVC $DATA_VOLUME in $APP_NAMESPACE, exists without the Secret $missing: a new password would not open the data it holds (ADR-012, condition 3). Remove the volume and the Secrets of the database together, then run task up again: task down removes the cluster, and both with it. Nothing was created."
}

# create NAME [USER]: the Secret NAME from a pipe, of type
# kubernetes.io/basic-auth with the keys username and password when USER is
# given, of type Opaque with the key password alone when it is not (the
# cache, ADR-015, condition 5). The password goes from /dev/urandom through
# tr and cut into the manifest that kubectl create reads on its standard
# input.
create() {
  {
    if [ -n "${2:-}" ]; then
      printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: %s\n  namespace: %s\ntype: kubernetes.io/basic-auth\nstringData:\n  username: %s\n  password: ' \
        "$1" "$APP_NAMESPACE" "$2"
    else
      printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: %s\n  namespace: %s\ntype: Opaque\nstringData:\n  password: ' \
        "$1" "$APP_NAMESPACE"
    fi
    head -c "$RANDOM_BYTES" /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c "1-$PASSWORD_LENGTH"
  } | kube create -f - >/dev/null ||
    die "the Secret $1 was not created; the messages of kubectl are above."
}

# verify NAME: the password of the new Secret NAME has its full length;
# otherwise the Secret goes, and task up stops. Only the length of its
# base64 form is read, through a pipe.
verify() {
  local length
  length="$(kube --namespace "$APP_NAMESPACE" get secret "$1" --output 'jsonpath={.data.password}' | wc -c | tr -d ' ')" ||
    die "cannot read back the Secret $1; the messages of kubectl are above."
  [ "$length" = "$PASSWORD_BASE64_LENGTH" ] && return 0
  kube --namespace "$APP_NAMESPACE" delete secret "$1" --ignore-not-found >/dev/null || :
  die "the password drawn for the Secret $1 is short; the Secret was removed. Run task up again."
}

# restart_cache: a new cache-auth only counts once the init container of the
# cache has written its hash, which it does at each start of the pod. When
# the Deployment cache is there, it restarts; on a new cluster it does not
# exist yet, and its first start reads the Secret.
restart_cache() {
  local state
  state="$(present deployment "$CACHE_DEPLOYMENT")"
  [ "$state" = yes ] || return 0
  kube --namespace "$APP_NAMESPACE" rollout restart "deployment/$CACHE_DEPLOYMENT" >/dev/null ||
    die "the Deployment $CACHE_DEPLOYMENT was not restarted after the new Secret $CACHE_SECRET; the messages of kubectl are above. Run task down, then task up."
  printf 'Secrets: the Deployment %s restarts to read the new %s.\n' "$CACHE_DEPLOYMENT" "$CACHE_SECRET"
}

# ensure NAME [USER]: NAME kept when it exists, created and checked when it
# does not.
ensure() {
  local state
  state="$(present secret "$1")"
  if [ "$state" = yes ]; then
    printf 'Secrets: %s kept.\n' "$1"
    return 0
  fi
  create "$1" "${2:-}"
  verify "$1"
  printf 'Secrets: %s created, %s random characters.\n' "$1" "$PASSWORD_LENGTH"
  if [ "$1" = "$CACHE_SECRET" ]; then
    restart_cache
  fi
}

up() {
  check
  kube apply --server-side -f "$NAMESPACE_FILE" >/dev/null ||
    die "the namespace $APP_NAMESPACE was not applied; the messages of kubectl are above. No Secret was created."
  ensure "$APP_SECRET" "$APP_USER"
  ensure "$SUPERUSER_SECRET" "$SUPERUSER"
  ensure "$CACHE_SECRET"
}

case "${1:-}" in
  up) up ;;
  *) die "usage: bash local/scripts/secrets.sh up" ;;
esac
