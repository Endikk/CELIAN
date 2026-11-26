#!/usr/bin/env bash
# The application layer of the local cluster (spec 001, plan, "Ce que fait
# task up", points 5, 7 and 8; contracts/task-cli.md).
#
# Usage: bash local/scripts/app.sh check
#        bash local/scripts/app.sh images | apply | database
#        bash local/scripts/app.sh ready PORT | reload PORT | down
#   check     the files of the composition are there; calls no kubectl and
#             creates nothing: task up runs it before it creates the cluster
#   images    builds the images of the API and the front under saas-b2b.invalid
#             (research RS-07), tags each with the first twelve digits of its
#             own image ID, and loads it into the cluster with kind load
#   apply     applies local/k8s/lite server-side (kubectl apply -k): the
#             local environment of the common layer, with the component of
#             the local target (research RS-01), the two images under the tag
#             that Kustomize sets
#   database  waits for the StatefulSet postgres, then until the database
#             answers an authenticated SELECT 1, with the user of db-auth,
#             through its Service (ADR-012, condition 6)
#   ready     waits for the Deployments of the API and the front, then until
#             the gateway, on 127.0.0.1 and the port PORT, answers /api/healthz
#             and the page of the front; prints their addresses
#   reload    task reload: images, apply and ready, defined once for task up
#             and for task reload (ADR-006, condition 6); the database and
#             its data are not touched
#   down      task app:down: deletes the namespace of the application, and
#             with it the database, its volume and its Secrets, and says how
#             much memory the cluster keeps; the cluster stays
# The cache is waited for by local/scripts/cache.sh, which task up runs
# between database and ready.
#
# The tag of an image follows the image: a build from the same sources hits
# the cache of the engine, gives the same ID and so the same tag, and the
# objects do not change; a change of the sources gives a new ID, a new tag,
# and a rollout of that Deployment alone. Kustomize sets the tag: a
# kustomization written in a folder of its own, outside the repository, lists
# local/k8s/lite as its base and the two tags under images, and goes with the
# end of the command. The base names an image without a build,
# saas-b2b.invalid/api:unbuilt, which no node can pull (.invalid resolves to
# no registry).
#
# The Secrets come before, from local/scripts/secrets.sh. The SELECT 1 runs
# in the container of Postgres, which mounts db-auth: the password goes from
# its file to the environment of psql inside the pod, and never through this
# machine. Every kubectl call goes through kube of lib/local-env.sh (S19).
# The commands that build or tag an image, or load it into the cluster, are
# listed at the head of Taskfile.yml.
set -euo pipefail

here="${BASH_SOURCE[0]}"
case "$here" in
  */*) here="${here%/*}" ;;
  *) here="." ;;
esac
# shellcheck disable=SC1091 # lib/local-env.sh is checked on its own
. "$here/lib/local-env.sh"
root="$(CDPATH='' cd -- "$here/../.." && pwd -P)"

# The one profile delivered until step 12 (tasks.md, gap 14).
readonly COMPOSITION="local/k8s/lite"
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
# The images that the project builds, under the reserved host (research
# RS-07): name, build context from the root, Dockerfile in the context.
readonly BUILT_HOST="saas-b2b.invalid"
readonly API_IMAGE="api"
readonly FRONT_IMAGE="front"
readonly API_CONTEXT="src"
readonly API_DOCKERFILE="Api/Dockerfile"
readonly FRONT_CONTEXT="src/front"
readonly FRONT_DOCKERFILE="Dockerfile"
# The Dockerfile stage that holds the image (src/Api/Dockerfile and
# src/front/Dockerfile), and the tag that the last build carries on the
# engine, from which the tag of the cluster is drawn.
readonly IMAGE_STAGE="runtime"
readonly BUILT_TAG="built"
readonly TAG_LENGTH=12
# The Deployments, how long they get to roll out, and how long the gateway
# gets to answer after that.
readonly API_DEPLOYMENT="api"
readonly FRONT_DEPLOYMENT="front"
readonly APP_ROLLOUT_WAIT="240s"
readonly GATEWAY_SECONDS=120
readonly GATEWAY_PAUSE_SECONDS=2
readonly GATEWAY_READ_SECONDS=5
# The host that the HTTPRoutes of the local layer name, and that the user
# types (tasks.md, gap 141; local/k8s/component/kustomization.yaml).
readonly GATEWAY_HOST="localhost"
# The node container of the cluster, whose memory task app:down reports.
readonly NODE_CONTAINER="$CLUSTER_NAME-control-plane"

die() {
  printf 'app: %s\n' "$1" >&2
  exit 1
}

check() {
  local file
  for file in local/k8s/lite/kustomization.yaml local/k8s/component/kustomization.yaml \
    local/k8s/component/app-config.yaml k8s/base/api.yaml k8s/base/front.yaml \
    src/Api/Dockerfile src/front/Dockerfile \
    local/data/kustomization.yaml local/data/statefulset.yaml local/data/service.yaml \
    local/data/network-policy.yaml local/data/init/10-app-role.sh local/data/cache/kustomization.yaml \
    local/data/cache/deployment.yaml local/data/cache/probe/job.yaml; do
    [ -f "$root/$file" ] || die "$file is missing. Restore it from the repository. Nothing was applied."
  done
}

# require_cluster: the images go into a cluster, and the manifests into it.
require_cluster() {
  kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME" ||
    die "the cluster $CLUSTER_NAME does not exist. Run task up first."
}

# build_image NAME CONTEXT DOCKERFILE: builds the stage runtime of the image
# NAME, tags it with the first characters of its ID, loads it into the
# cluster. A build that fails prints its own messages, and stops here.
build_image() {
  local name="$1" context="$2" dockerfile="$3" tag out
  docker build --quiet --target "$IMAGE_STAGE" --tag "$BUILT_HOST/$name:$BUILT_TAG" \
    --file "$root/$context/$dockerfile" "$root/$context" >/dev/null ||
    die "the image $name was not built; the messages of docker are above."
  tag="$(image_tag "$name")"
  docker tag "$BUILT_HOST/$name:$BUILT_TAG" "$BUILT_HOST/$name:$tag" ||
    die "the image $name was not tagged $tag."
  out="$(kind load docker-image "$BUILT_HOST/$name:$tag" --name "$CLUSTER_NAME" 2>&1)" || {
    printf '%s\n' "$out" >&2
    die "the image $BUILT_HOST/$name:$tag was not loaded into the cluster $CLUSTER_NAME."
  }
  printf 'Image: %s/%s:%s built and loaded.\n' "$BUILT_HOST" "$name" "$tag"
}

# image_tag NAME: the first characters of the ID of the last build of NAME.
image_tag() {
  local id
  id="$(docker image inspect --format '{{.Id}}' "$BUILT_HOST/$1:$BUILT_TAG")" ||
    die "no image $BUILT_HOST/$1:$BUILT_TAG on the engine: run task up, which builds it."
  id="${id#sha256:}"
  printf '%s' "${id:0:$TAG_LENGTH}"
}

images() {
  check
  require_cluster
  build_image "$API_IMAGE" "$API_CONTEXT" "$API_DOCKERFILE"
  build_image "$FRONT_IMAGE" "$FRONT_CONTEXT" "$FRONT_DOCKERFILE"
}

# climb DIR: "../" once for each element of the physical path DIR, which
# leads from DIR to the root of the file system. Kustomize takes a base
# folder by a relative path only.
climb() {
  local path="${1#/}" up=""
  while [ -n "$path" ]; do
    up="$up../"
    case "$path" in
      */*) path="${path#*/}" ;;
      *) path="" ;;
    esac
  done
  printf '%s' "$up"
}

apply() {
  local api_tag front_tag work
  check
  api_tag="$(image_tag "$API_IMAGE")"
  front_tag="$(image_tag "$FRONT_IMAGE")"
  work="$(mktemp -d)"
  # shellcheck disable=SC2064 # the folder is known now, and removed whatever happens
  trap "rm -rf '${work:?}'" EXIT
  work="$(CDPATH='' cd -- "$work" && pwd -P)"
  printf 'apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nresources:\n  - %s%s\nimages:\n' \
    "$(climb "$work")" "${root#/}/$COMPOSITION" >"$work/kustomization.yaml"
  printf '  - name: %s/%s\n    newTag: "%s"\n' "$BUILT_HOST" "$API_IMAGE" "$api_tag" \
    "$BUILT_HOST" "$FRONT_IMAGE" "$front_tag" >>"$work/kustomization.yaml"
  kube apply --server-side -k "$work" >/dev/null ||
    die "$COMPOSITION was not applied; the messages of kubectl are above."
  printf 'Application: %s applied in %s, images tagged %s and %s.\n' "$COMPOSITION" "$APP_NAMESPACE" "$api_tag" "$front_tag"
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

database() {
  local answer waited=0
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

# http_status PORT PATH: the status code that GET PATH gets on 127.0.0.1:PORT
# under the Host of the routes, read by bash itself through /dev/tcp (no
# curl); fails without an HTTP answer.
http_status() {
  local line
  line="$(
    exec 3<>"/dev/tcp/127.0.0.1/$1" || exit 1
    printf 'GET %s HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n' "$2" "$GATEWAY_HOST" >&3
    IFS= read -r -t "$GATEWAY_READ_SECONDS" first <&3 || exit 1
    printf '%s' "$first"
  )" 2>/dev/null || return 1
  [[ $line =~ ^HTTP/1\.[01]\ ([0-9][0-9][0-9]) ]] || return 1
  printf '%s' "${BASH_REMATCH[1]}"
}

# wait_status PORT PATH: until the gateway answers 200 for PATH.
wait_status() {
  local waited=0 code=""
  while :; do
    code="$(http_status "$1" "$2")" || code=""
    [ "$code" = 200 ] && return 0
    [ "$waited" -lt "$GATEWAY_SECONDS" ] ||
      die "the gateway does not answer 200 for $2 on 127.0.0.1:$1 within $GATEWAY_SECONDS s (last answer: ${code:-none}). Look at the pods: kubectl --kubeconfig $KUBECONFIG_FILE --context $KUBE_CONTEXT --namespace $APP_NAMESPACE get pods."
    sleep "$GATEWAY_PAUSE_SECONDS"
    waited=$((waited + GATEWAY_PAUSE_SECONDS))
  done
}

ready() {
  local port="${1:-}" deployment
  [[ $port =~ ^[0-9]+$ ]] || die "usage: bash local/scripts/app.sh ready PORT"
  for deployment in "$API_DEPLOYMENT" "$FRONT_DEPLOYMENT"; do
    kube --namespace "$APP_NAMESPACE" rollout status "deployment/$deployment" --timeout="$APP_ROLLOUT_WAIT" >/dev/null ||
      die "the Deployment $deployment is not available within $APP_ROLLOUT_WAIT. Look at its pods: kubectl --kubeconfig $KUBECONFIG_FILE --context $KUBE_CONTEXT --namespace $APP_NAMESPACE describe pods --selector app.kubernetes.io/name=$deployment."
  done
  wait_status "$port" /api/healthz
  wait_status "$port" /
  printf 'Ready: the API and the front answer through the gateway.\n'
  printf 'Front: http://%s:%s/\n' "$GATEWAY_HOST" "$port"
  printf 'API: http://%s:%s/api/\n' "$GATEWAY_HOST" "$port"
}

reload() {
  images
  apply
  ready "${1:-}"
}

# kept_memory: the memory that the node container uses, as docker stats
# shows it, without the limit that follows the slash.
kept_memory() {
  local usage
  usage="$(docker stats --no-stream --format '{{.MemUsage}}' "$NODE_CONTAINER" 2>/dev/null)" || usage=""
  usage="${usage%% /*}"
  printf '%s' "${usage:-unknown}"
}

down() {
  kube delete namespace "$APP_NAMESPACE" --ignore-not-found --wait=true --timeout=240s >/dev/null ||
    die "the namespace $APP_NAMESPACE was not deleted; the messages of kubectl are above. Run task down to remove the cluster."
  printf 'Application: namespace %s deleted, with the database, its volume and its Secrets; the cluster %s stays.\n' "$APP_NAMESPACE" "$CLUSTER_NAME"
  printf 'Memory: the cluster %s keeps %s in use on the engine. task down removes it.\n' "$CLUSTER_NAME" "$(kept_memory)"
}

case "${1:-}" in
  check) check ;;
  images) images ;;
  apply) apply ;;
  database) database ;;
  ready) ready "${2:-}" ;;
  reload) reload "${2:-}" ;;
  down) down ;;
  *) die "usage: bash local/scripts/app.sh check | images | apply | database | ready PORT | reload PORT | down" ;;
esac
