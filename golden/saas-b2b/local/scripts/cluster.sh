#!/usr/bin/env bash
# The kind cluster of the local environment (spec 001, plan, "Ce que fait
# task up", point 2; contracts/task-cli.md).
#
# Usage: bash local/scripts/cluster.sh up|down
#   up    creates the cluster from local/kind/cluster.yaml, or reuses the one
#         that exists, and writes the kubeconfig of the project
#   down  deletes the cluster and the kubeconfig of the project
#
# Every kind command names the cluster and the kubeconfig of the project,
# every kubectl command its context (S19): the default kubeconfig of the
# user, or a KUBECONFIG of theirs, is neither read nor changed (FR-019,
# E24). The kubeconfig lives outside the repository, in mode 600 (research
# RS-21). Commands that create or remove something are listed at the head
# of Taskfile.yml (ADR-011, condition 11).
set -euo pipefail
# The kubeconfig and its folder are created readable by their owner alone.
umask 077

here="${BASH_SOURCE[0]}"
case "$here" in
  */*) here="${here%/*}" ;;
  *) here="." ;;
esac
# shellcheck disable=SC1091 # lib/local-env.sh is checked on its own
. "$here/lib/local-env.sh"
# kind resolves the hostPath of extraMounts from the folder where it runs
# (research RS-13): every kind command runs from the root of the golden repo.
root="$(CDPATH='' cd -- "$here/../.." && pwd)"
CDPATH='' cd -- "$root"

readonly KIND_CONFIG="local/kind/cluster.yaml"
# How long kind waits for the control plane to be ready at creation; it took
# 26.8 s with the node image in cache, 73.7 s cold, in BENCH-003 (ADR-004).
readonly CREATE_WAIT="180s"
# How long a reused cluster gets to answer.
readonly REUSE_TIMEOUT="20s"

die() {
  printf 'cluster: %s\n' "$1" >&2
  exit 1
}

cluster_exists() {
  local clusters
  clusters="$(kind get clusters 2>/dev/null)" || die "kind get clusters failed: check the container engine, then run the task again."
  printf '%s\n' "$clusters" | grep -qx -- "$CLUSTER_NAME"
}

up() {
  [ -f "$KIND_CONFIG" ] || die "$KIND_CONFIG is missing: the cluster cannot be created. Nothing was created."
  [ -d local/mirror/certs.d ] || die "local/mirror/certs.d is missing: the node would not find the mirror. Nothing was created."
  mkdir -p "${KUBECONFIG_FILE%/*}"
  if cluster_exists; then
    printf 'Cluster: %s exists, reused.\n' "$CLUSTER_NAME"
    kind export kubeconfig --name "$CLUSTER_NAME" --kubeconfig "$KUBECONFIG_FILE"
    if ! kube --request-timeout="$REUSE_TIMEOUT" get --raw /readyz >/dev/null; then
      die "the cluster $CLUSTER_NAME exists but does not answer. Run task down, then task up."
    fi
  else
    printf 'Cluster: creating %s from %s.\n' "$CLUSTER_NAME" "$KIND_CONFIG"
    kind create cluster --name "$CLUSTER_NAME" --config "$KIND_CONFIG" \
      --kubeconfig "$KUBECONFIG_FILE" --wait "$CREATE_WAIT"
  fi
  chmod 600 "$KUBECONFIG_FILE"
  printf 'Cluster: %s ready; kubeconfig %s, context %s.\n' "$CLUSTER_NAME" "$KUBECONFIG_FILE" "$KUBE_CONTEXT"
}

down() {
  if cluster_exists; then
    kind delete cluster --name "$CLUSTER_NAME" --kubeconfig "$KUBECONFIG_FILE"
    printf 'Cluster: %s deleted.\n' "$CLUSTER_NAME"
  else
    printf 'Cluster: no cluster %s.\n' "$CLUSTER_NAME"
  fi
  # The file named only that cluster; kind has removed its entries.
  rm -f -- "$KUBECONFIG_FILE"
}

case "${1:-}" in
  up) up ;;
  down) down ;;
  *) die "usage: bash local/scripts/cluster.sh up|down" ;;
esac
