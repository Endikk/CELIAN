#!/usr/bin/env bash
# control: E10
# carries: FR-016, SC-009; ADR-004, condition 7; ADR-005, condition 4; ADR-006, condition 4; ADR-011, conditions 1 and 10; ADR-012, condition 11
#
# T2 of the lite profile (spec 001, T124): after a first task up with the
# network, task down, then the public registries cut for the cluster alone,
# task up creates the cluster again and reaches "ready" through the mirror,
# which holds only the capability pull (ADR-011, condition 1). The cut is the
# one of BENCH-010 (lib/offline.sh), on a copy of the golden repo; nothing of
# the machine's network changes.
# - the first task up and task down succeed, the volume of the mirror stays;
# - the second task up succeeds within the limit, and shows its steps and its
#   total: the cluster is new, so every image of the stack came through the
#   mirror;
# - no container of the cluster waits on a pull;
# - the mirror logged GET requests for the manifest and the blobs of
#   library/postgres and of envoyproxy/gateway with a 200 (it served them);
# - a pod in imagePullPolicy: Always on the Postgres image of the stack, by
#   digest (postgres:18.7-trixie), starts: the kubelet asks the registry again
#   and the mirror answers by itself, with the capability pull alone;
# - the cut is real: two witness pods, on a docker.io image and on a quay.io
#   image that no cache holds, fail their pull. The quay.io one names the dead
#   end 127.0.0.1:9. The docker.io one asks the mirror first, which cannot reach
#   its own upstream and answers 503: containerd keeps that answer, so the
#   error names the mirror and the 503 (tasks.md, gap 165).
# The result of a failure reopens ADR-011 (condition 1) and goes up to the DSI.
set -uo pipefail
# shellcheck disable=SC1091 # lib/offline.sh is checked on its own
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/offline.sh"

readonly ALWAYS_NAMESPACE="e2e-offline-always"
readonly STEPS="preflight cluster mirror secrets platform images application database cache ready"

offline_work || exit 2
cleanup() {
  remove_client_namespace "$ALWAYS_NAMESPACE"
  (CDPATH='' cd -- "$E2E_ROOT" && task down >/dev/null 2>&1) || :
  rm -rf "${OFFLINE_WORK:?}"
}
trap cleanup EXIT
offline_copy_repo || {
  fail "could not copy the golden repo into $OFFLINE_WORK"
  e2e_finish
}

# 1. A first start, with the network, from an empty mirror, then task down.
must_succeed down || e2e_finish
must_succeed mirror:purge || e2e_finish
up_within "$OFFLINE_UP_LIMIT_SECONDS" || e2e_finish
printf 'note: the first task up, with the network, took %s s.\n' "$ELAPSED"
must_succeed down || e2e_finish
if ! volume_exists "$E2E_VOLUME"; then
  fail "task down removed the mirror volume $E2E_VOLUME: nothing is left to restart from"
  e2e_finish
fi
if container_exists "$E2E_MIRROR" || cluster_exists; then
  fail "task down left the cluster or the mirror container"
fi

# 2. The cut, then the restart.
if ! offline_cut; then
  fail "could not cut the registries in the copy of the golden repo"
  e2e_finish
fi
up_within "$OFFLINE_UP_LIMIT_SECONDS" || e2e_finish
printf 'note: the task up without a public registry took %s s.\n' "$ELAPSED"
for step in $STEPS; do
  printf '%s\n' "$OUTPUT" | grep -qE "^Step $step: [0-9]+ s\.$" || fail "the output of the task up without registry has no line \"Step $step: <n> s.\""
done
expect_output "Ready: the API and the front answer through the gateway."

# 3. Nothing waits on a pull, and the mirror served what the node pulled.
waiting="$(kube_e2e get pods --all-namespaces \
  --output 'jsonpath={range .items[*]}{range .status.initContainerStatuses[*]}{.state.waiting.reason}{" "}{.image}{"\n"}{end}{range .status.containerStatuses[*]}{.state.waiting.reason}{" "}{.image}{"\n"}{end}{end}' |
  grep -E '^(ErrImagePull|ImagePullBackOff) ' || true)"
[ -z "$waiting" ] || fail "a container of the cluster waits on a pull: $waiting"
for repository in library/postgres envoyproxy/gateway; do
  served="$(mirror_logged_gets "$repository")"
  if [ "${served:-0}" -gt 0 ]; then
    printf 'note: the mirror served %s requests for %s with a 200.\n' "$served" "$repository"
  else
    fail "the log of the mirror shows no GET of $repository answered 200: the node did not pull it through the mirror"
  fi
done

# 4. imagePullPolicy: Always on the image of Postgres, mirror in pull alone.
if client_namespace "$ALWAYS_NAMESPACE"; then
  always_pod "$ALWAYS_NAMESPACE" always-postgres
  if [ "$STATUS" -ne 0 ]; then
    fail "the pod in imagePullPolicy: Always on $(postgres_image) did not succeed without a registry: ADR-011 (condition 1) reopens ($OUTPUT)"
  else
    case "$OUTPUT" in
      *"Pulling:"*) printf 'note: the kubelet pulled the image again (Always) and the mirror answered.\n' ;;
      *) fail "the pod in imagePullPolicy: Always shows no Pulling event: the kubelet did not ask the registry (events: $OUTPUT)" ;;
    esac
  fi
else
  fail "could not create the namespace $ALWAYS_NAMESPACE"
fi

# 5. The cut is real: the witness pods cannot pull.
kube_e2e create namespace "$OFFLINE_WITNESS_NAMESPACE" >/dev/null 2>&1
message="$(witness_pull w-docker-io "$OFFLINE_WITNESS_DOCKER")"
case "$message" in
  *"http://$E2E_MIRROR:5000/"*"503 Service Unavailable"*) printf 'note: w-docker-io fails its pull: the mirror, cut from its upstream, answers 503.\n' ;;
  *) fail "the witness pod w-docker-io did not fail with the 503 of the mirror: the cut leaks (got: $message)" ;;
esac
message="$(witness_pull w-quay-io "$OFFLINE_WITNESS_QUAY")"
case "$message" in
  *127.0.0.1:9*) printf 'note: w-quay-io fails its pull at the dead end, as expected.\n' ;;
  *) fail "the witness pod w-quay-io did not fail at the dead end 127.0.0.1:9: the cut leaks (got: $message)" ;;
esac
kube_e2e delete namespace "$OFFLINE_WITNESS_NAMESPACE" --ignore-not-found --wait=false >/dev/null 2>&1 || :

e2e_finish
