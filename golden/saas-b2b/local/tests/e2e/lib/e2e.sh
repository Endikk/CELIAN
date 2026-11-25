# shellcheck shell=bash
# shellcheck disable=SC2034 # the E2E_ values are read by the tests that source this file
# Shared helpers of the tests on kind (spec 001, local/tests/e2e/). Sourced
# by each test, never run on its own. The tests drive the real tasks, task
# up and task down first, against the real container engine and kind:
# local/tests/e2e/run.sh runs them in order, under `task test:e2e`.
#
# The names below are what the tests expect task up to create. They are
# written here on purpose, apart from local/scripts/lib/local-env.sh: a
# change of name there must break a test, not move it along.
#
# Run outside run.sh, a test uses the HOME it gets, so the kubeconfig of the
# project lands in its .kube/. run.sh gives the tests a HOME of their own,
# and sets E2E_SANDBOX_HOME=1.

E2E_ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)"
E2E_CLUSTER="saas-b2b"
E2E_CONTEXT="kind-$E2E_CLUSTER"
E2E_MIRROR="saas-b2b-mirror"
E2E_VOLUME="saas-b2b-mirror"
E2E_LABEL="invalid.saas-b2b.role=registry-mirror"
E2E_KUBECONFIG="${HOME:?}/.kube/kind-$E2E_CLUSTER"
# kind labels each node container with its cluster (kind v0.33.0,
# pkg/cluster/internal/providers/docker/constants.go).
E2E_NODE_FILTER="label=io.x-k8s.kind.cluster=$E2E_CLUSTER"
# The host ports of the gateway, as local/tasks/local.yml and
# local/kind/cluster.yaml set them (research RS-20), and the Gateway of the
# common layer, in the namespace of the application (contracts/layers.md).
E2E_GATEWAY_HTTP_PORT=18080
E2E_GATEWAY_HTTPS_PORT=18443
E2E_APP_NAMESPACE="saas-b2b"
E2E_GATEWAY="saas-b2b"

E2E_FAILURES=0
OUTPUT=""
STATUS=0

for tool in task docker kind kubectl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf '%s is not on PATH: the tests on kind need task, docker, kind and kubectl.\n' "$tool"
    exit 1
  fi
done

fail() {
  E2E_FAILURES=$((E2E_FAILURES + 1))
  printf 'FAIL: %s\n' "$1"
}

# show_output: the output of the last task, indented, for a failure.
show_output() {
  printf '  exit status %s, output:\n' "$STATUS"
  printf '%s\n' "$OUTPUT" | LC_ALL=C cat -v | sed 's/^/    /'
}

# run_task ARG...: runs task ARG... in the golden repo, with the environment
# of the test; sets OUTPUT and STATUS.
run_task() {
  STATUS=0
  OUTPUT="$(CDPATH='' cd -- "$E2E_ROOT" && task "$@" 2>&1)" || STATUS=$?
}

# must_succeed ARG...: runs task ARG..., and fails the test if it fails.
must_succeed() {
  run_task "$@"
  if [ "$STATUS" -ne 0 ]; then
    fail "task $* failed"
    show_output
    return 1
  fi
}

expect_output() {
  case "$OUTPUT" in
    *"$1"*) ;;
    *)
      fail "the output of the last task does not say: $1"
      show_output
      ;;
  esac
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

container_exists() {
  docker container inspect --format '{{.Name}}' "$1" >/dev/null 2>&1
}

volume_exists() {
  docker volume inspect --format '{{.Name}}' "$1" >/dev/null 2>&1
}

cluster_exists() {
  kind get clusters 2>/dev/null | grep -qx "$E2E_CLUSTER"
}

# kube_e2e ARG...: kubectl on the cluster of the project, through its
# kubeconfig and its context, as the tasks do (S19).
kube_e2e() {
  kubectl --kubeconfig "$E2E_KUBECONFIG" --context "$E2E_CONTEXT" "$@"
}

# The zot image of the project, as local/tasks/local.yml pins it. The decoys
# of E22 use it, so that no other image is pulled.
mirror_image() {
  awk '$1 == "MIRROR_IMAGE:" { print $2; exit }' "$E2E_ROOT/local/tasks/local.yml"
}

e2e_finish() {
  if [ "$E2E_FAILURES" -gt 0 ]; then
    printf '%s failure(s).\n' "$E2E_FAILURES"
    exit 1
  fi
  printf 'passed.\n'
}
