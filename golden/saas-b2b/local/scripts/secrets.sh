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
#       runs restarts that Deployment. Last, gateway-tls (type
#       kubernetes.io/tls, tls.crt and tls.key), likewise only when it is
#       missing, from the command of research RS-10 below. A gateway-tls
#       that exists is kept, and a warning, without stopping, says when its
#       certificate expires in less than 30 days.
#
# gateway-tls holds no password: one openssl req writes its key and its
# self-signed certificate to its standard output, awk labels the two PEM
# blocks as the keys of the Secret, and the manifest goes through a pipe to
# kubectl create -f -, like the passwords. The key never reaches a file, a
# variable or an argument (ADR-007, condition 1); S04 refuses the forms that
# would. openssl and awk are checked by the preflight checks, before anything
# is created (tasks.md, gap 80).
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
readonly API_DEPLOYMENT="api"
# The password: PASSWORD_LENGTH alphanumeric characters kept out of
# RANDOM_BYTES bytes of /dev/urandom, about a quarter of which are
# alphanumeric. Its base64 form in the Secret is PASSWORD_BASE64_LENGTH
# characters long, which up checks once the Secret is created.
readonly PASSWORD_LENGTH=40
readonly RANDOM_BYTES=4096
readonly PASSWORD_BASE64_LENGTH=56
# The Secret of the Gateway (contracts/secrets.md; research RS-10). Its
# certificate is self-signed, valid TLS_DAYS days, and task up warns when less
# than TLS_WARNING_DAYS days are left (decision of the DSI of 2026-11-26).
readonly TLS_SECRET="gateway-tls"
readonly TLS_DAYS=365
readonly TLS_WARNING_DAYS=30
readonly SECONDS_PER_DAY=86400

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

# restart_api: the API reads the password of the cache from its mounted file
# and keeps it in memory. A new cache-auth leaves it with the old password,
# which the cache now refuses (WRONGPASS), so the Deployment api restarts too
# when it is there (tasks.md, gap 107). The client also reads the file again
# after a failure, once the kubelet has refreshed it; this restart makes it
# immediate.
restart_api() {
  local state
  state="$(present deployment "$API_DEPLOYMENT")"
  [ "$state" = yes ] || return 0
  kube --namespace "$APP_NAMESPACE" rollout restart "deployment/$API_DEPLOYMENT" >/dev/null ||
    die "the Deployment $API_DEPLOYMENT was not restarted after the new Secret $CACHE_SECRET; the messages of kubectl are above. Run task down, then task up."
  printf 'Secrets: the Deployment %s restarts to read the new %s.\n' "$API_DEPLOYMENT" "$CACHE_SECRET"
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
    restart_api
  fi
}

# create_tls: the Secret gateway-tls from a pipe (research RS-10). One
# openssl req makes a P-256 key and a self-signed certificate of TLS_DAYS
# days for localhost and 127.0.0.1, a certificate of a server and not of an
# authority, and writes both to its standard output (-keyout /dev/stdout:
# without it, req writes the key to the file of its configuration). awk
# labels the two PEM blocks as the keys tls.key and tls.crt of stringData, in
# whatever order they come. The messages of openssl are cut: they are banners
# of progress. A failure of openssl is the status of the pipeline (pipefail),
# and a manifest cut short is refused by the API, which wants both keys in a
# Secret of this type. -nodes leaves the key without a passphrase; -noenc
# replaces it in OpenSSL 3 but the LibreSSL 3.3.6 of macOS refuses it
# (research RS-10). A creation, never an apply, so that the key is not copied
# into last-applied-configuration.
create_tls() {
  {
    printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: %s\n  namespace: %s\ntype: kubernetes.io/tls\nstringData:\n' \
      "$TLS_SECRET" "$APP_NAMESPACE"
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
      -keyout /dev/stdout -out /dev/stdout -days "$TLS_DAYS" -subj '/CN=localhost' \
      -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1' \
      -addext 'basicConstraints=critical,CA:FALSE' \
      -addext 'keyUsage=critical,digitalSignature' \
      -addext 'extendedKeyUsage=serverAuth' 2>/dev/null |
      awk '/^-----BEGIN [A-Z ]*PRIVATE KEY-----$/ { print "  tls.key: |" }
           /^-----BEGIN CERTIFICATE-----$/ { print "  tls.crt: |" }
           { print "    " $0 }'
  } | kube create -f - >/dev/null ||
    die "the Secret $TLS_SECRET was not created: kubectl, or the command that makes the key, failed; the messages of the second are cut, those of kubectl are above."
}

# verify_tls: both keys of the new gateway-tls are filled; otherwise the
# Secret goes, and task up stops. Only the length of each value, in base64,
# is read, through a pipe, as verify does for a password.
verify_tls() {
  local key length
  for key in tls.crt tls.key; do
    length="$(kube --namespace "$APP_NAMESPACE" get secret "$TLS_SECRET" --output "jsonpath={.data.${key//./\\.}}" | wc -c | tr -d ' ')" ||
      die "cannot read back the Secret $TLS_SECRET; the messages of kubectl are above."
    if [ "$length" = 0 ]; then
      kube --namespace "$APP_NAMESPACE" delete secret "$TLS_SECRET" --ignore-not-found >/dev/null || :
      die "the key $key of the Secret $TLS_SECRET is empty; the Secret was removed. Run task up again."
    fi
  done
}

# certificate_outlives SECONDS: success when the certificate of gateway-tls is
# still valid SECONDS from now. The public certificate goes through a pipe to
# openssl x509 -checkend, whose answer is its status: 0 valid, 1 not, which an
# unreadable certificate gives too.
certificate_outlives() {
  kube --namespace "$APP_NAMESPACE" get secret "$TLS_SECRET" --output 'go-template={{index .data "tls.crt" | base64decode}}' |
    openssl x509 -noout -checkend "$1" >/dev/null 2>/dev/null
}

# warn_expiry: a gateway-tls that exists is kept, so its certificate ages
# (TLS_DAYS days). Less than TLS_WARNING_DAYS days left, or none: task up says
# so on stderr and goes on, without recreating anything. The way out is to
# delete the Secret and run task up.
warn_expiry() {
  if ! certificate_outlives 0; then
    printf 'task up: warning: the certificate of %s has expired, or cannot be read. The HTTPS listener serves it as it is. Delete the Secret, then run task up again: kubectl delete secret %s --namespace %s.\n' \
      "$TLS_SECRET" "$TLS_SECRET" "$APP_NAMESPACE" >&2
  elif ! certificate_outlives "$((TLS_WARNING_DAYS * SECONDS_PER_DAY))"; then
    printf 'task up: warning: the certificate of %s expires in less than %s days. Delete the Secret, then run task up again to get a new one: kubectl delete secret %s --namespace %s.\n' \
      "$TLS_SECRET" "$TLS_WARNING_DAYS" "$TLS_SECRET" "$APP_NAMESPACE" >&2
  fi
}

# ensure_tls: gateway-tls kept, with a warning when its certificate is near
# its end, or created and checked when it is missing.
ensure_tls() {
  local state
  state="$(present secret "$TLS_SECRET")"
  if [ "$state" = yes ]; then
    printf 'Secrets: %s kept.\n' "$TLS_SECRET"
    warn_expiry
    return 0
  fi
  create_tls
  verify_tls
  printf 'Secrets: %s created, a self-signed certificate for %s days.\n' "$TLS_SECRET" "$TLS_DAYS"
}

up() {
  check
  kube apply --server-side -f "$NAMESPACE_FILE" >/dev/null ||
    die "the namespace $APP_NAMESPACE was not applied; the messages of kubectl are above. No Secret was created."
  ensure "$APP_SECRET" "$APP_USER"
  ensure "$SUPERUSER_SECRET" "$SUPERUSER"
  ensure "$CACHE_SECRET"
  ensure_tls
}

case "${1:-}" in
  up) up ;;
  *) die "usage: bash local/scripts/secrets.sh up" ;;
esac
