#!/usr/bin/env bash
# control: E24
# carries: FR-019; ADR-004, condition 9; research RS-21
#
# With a decoy kubeconfig in KUBECONFIG, whose current context points at
# another cluster, task up succeeds and leaves the decoy as it was: every
# command names the kubeconfig of the project (S19). Under run.sh, a second
# decoy sits at the default path, $HOME/.kube/config, and stays as it was
# too. The cluster answers through the kubeconfig of the project.
set -uo pipefail
# shellcheck disable=SC1091 # lib/e2e.sh is checked on its own
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/e2e.sh"

decoys="$(mktemp -d)" || exit 2
trap 'rm -rf "${decoys:?}"' EXIT

# A kubeconfig that names a cluster of the documentation range 192.0.2.0/24,
# with no credential.
write_decoy() {
  printf '%s\n' \
    'apiVersion: v1' \
    'kind: Config' \
    'clusters:' \
    '- name: decoy' \
    '  cluster:' \
    '    server: https://192.0.2.10:6443' \
    'contexts:' \
    '- name: decoy' \
    '  context:' \
    '    cluster: decoy' \
    '    user: decoy' \
    'current-context: decoy' \
    'users:' \
    '- name: decoy' \
    '  user: {}' >"$1"
}

write_decoy "$decoys/kubeconfig"
decoy_sum="$(sha256_of "$decoys/kubeconfig")"
default_decoy=""
if [ "${E2E_SANDBOX_HOME:-}" = 1 ]; then
  mkdir -p "$HOME/.kube"
  default_decoy="$HOME/.kube/config"
  write_decoy "$default_decoy"
fi

KUBECONFIG="$decoys/kubeconfig" must_succeed up || e2e_finish

if [ "$(sha256_of "$decoys/kubeconfig")" != "$decoy_sum" ]; then
  fail "task up changed the kubeconfig named by KUBECONFIG"
fi
if [ -n "$default_decoy" ] && [ "$(sha256_of "$default_decoy")" != "$decoy_sum" ]; then
  fail "task up changed the default kubeconfig, \$HOME/.kube/config"
fi
if ! KUBECONFIG="$decoys/kubeconfig" kubectl --kubeconfig "$E2E_KUBECONFIG" --context "$E2E_CONTEXT" \
  --request-timeout=20s get --raw /readyz >/dev/null 2>&1; then
  fail "the cluster does not answer through the kubeconfig of the project, $E2E_KUBECONFIG"
fi

e2e_finish
