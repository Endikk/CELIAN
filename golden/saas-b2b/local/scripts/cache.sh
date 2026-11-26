#!/usr/bin/env bash
# "Ready" for the cache of the local layer (spec 001, plan, "Ce que fait
# task up"; ADR-015, condition 17): an authenticated PING that gets PONG
# through the Service cache, as in BENCH-014, and not a pod Ready.
#
# Usage: bash local/scripts/cache.sh wait
#   wait  once task up has applied the application layer, which holds the
#         cache (local/data/cache/, through local/k8s/component/), waits for
#         the Deployment cache, then runs the probe Job of
#         local/data/cache/probe/job.yaml and waits for its answer. The Job
#         goes once it answers, either way.
#
# The probe reads the password of cache-auth by secretKeyRef, inside the
# cluster: nothing here reads, prints or passes it. Every kubectl call goes
# through kube of lib/local-env.sh, which names the kubeconfig of the
# project and its context (S19). Nothing here creates or removes a
# container, a network or a volume of the engine.
set -euo pipefail

here="${BASH_SOURCE[0]}"
case "$here" in
  */*) here="${here%/*}" ;;
  *) here="." ;;
esac
# shellcheck disable=SC1091 # lib/local-env.sh is checked on its own
. "$here/lib/local-env.sh"
root="$(CDPATH='' cd -- "$here/../.." && pwd)"

# The namespace of the application and of its data (k8s/base/namespace.yaml;
# ADR-012, condition 9), the APP_NAMESPACE of lib/local-env.sh.
readonly CACHE_NAMESPACE="$APP_NAMESPACE"
readonly PROBE_FILE="$root/local/data/cache/probe/job.yaml"
readonly PROBE_JOB="cache-probe"
# The Deployment pulls its image through the mirror at the first start;
# BENCH-014 measured a median of 5.5 s to "ready" (M1, ADR-015).
readonly ROLLOUT_WAIT="180s"
# Longer than activeDeadlineSeconds of the Job (150 s), so that the Job
# states its own failure first.
readonly PROBE_SECONDS=170
readonly POLL_SECONDS=2

die() {
  printf 'cache: %s\n' "$1" >&2
  exit 1
}

kube_ns() {
  kube --namespace "$CACHE_NAMESPACE" "$@"
}

remove_probe() {
  kube_ns delete job "$PROBE_JOB" --ignore-not-found --wait=true >/dev/null
}

wait_ready() {
  local status deadline
  [ -f "$PROBE_FILE" ] || die "local/data/cache/probe/job.yaml is missing. Restore it from the repository."
  kube_ns rollout status deployment/cache --timeout="$ROLLOUT_WAIT" >/dev/null ||
    die "the Deployment cache is not available within $ROLLOUT_WAIT; the messages of kubectl are above. Run task down, then task up."
  remove_probe || die "the previous probe Job could not be removed; the messages of kubectl are above."
  kube create -f "$PROBE_FILE" >/dev/null || die "the probe Job was not created; the messages of kubectl are above."
  deadline=$((SECONDS + PROBE_SECONDS))
  while :; do
    status="$(kube_ns get job "$PROBE_JOB" --output 'jsonpath={.status.succeeded}/{.status.failed}')" ||
      die "cannot read the probe Job; the messages of kubectl are above."
    case "$status" in
      1/*) break ;;
      */1)
        kube_ns logs "job/$PROBE_JOB" >&2 || :
        remove_probe || :
        die "no authenticated PING through the Service cache got PONG (ADR-015, condition 17); the answer of the probe is above. Run task down, then task up."
        ;;
    esac
    if [ "$SECONDS" -ge "$deadline" ]; then
      remove_probe || :
      die "the probe Job gave no answer within $PROBE_SECONDS s. Run task down, then task up."
    fi
    sleep "$POLL_SECONDS"
  done
  remove_probe || die "the probe Job answered, but could not be removed; the messages of kubectl are above."
  printf 'Cache: ready, an authenticated PING through the Service cache got PONG.\n'
}

case "${1:-}" in
  wait) wait_ready ;;
  *) die "usage: bash local/scripts/cache.sh wait" ;;
esac
