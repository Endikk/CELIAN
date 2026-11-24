#!/usr/bin/env bash
# control: P05
# carries: FR-019; ADR-004, condition 9; research RS-21; GATE 1, no GKE context on the machine
#
# A kubeconfig of the user whose current context points at another cluster
# is ignored: the checks pass, kubectl is called only for its client
# version, which reads no kubeconfig, and the user's files stay as they
# were. Step 6 extends this control to the commands that reach the local
# cluster through the project kubeconfig. Simulated binaries only
# (lib/harness.sh).
set -uo pipefail
# shellcheck disable=SC1091 # lib/harness.sh is checked on its own
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

foreign_context="gke_foreign-project_europe-west1_prod"

# kubeconfig_of CONTEXT FILE: a kubeconfig whose current context is CONTEXT.
kubeconfig_of() {
  {
    printf 'apiVersion: v1\n'
    printf 'kind: Config\n'
    printf 'current-context: %s\n' "$1"
    printf 'contexts:\n'
    printf '  - name: %s\n' "$1"
    printf '    context:\n'
    printf '      cluster: %s\n' "$1"
    printf '      user: %s\n' "$1"
    printf 'clusters:\n'
    printf '  - name: %s\n' "$1"
    printf '    cluster:\n'
    printf '      server: https://203.0.113.10\n'
    printf 'users:\n'
    printf '  - name: %s\n' "$1"
    printf '    user: {}\n'
  } >"$2"
}

mkdir -p "$SANDBOX/home/.kube"
kubeconfig_of "$foreign_context" "$SANDBOX/home/.kube/config"
kubeconfig_of "${foreign_context}-env" "$SANDBOX/user-kubeconfig"
before="$(cksum "$SANDBOX/home/.kube/config" "$SANDBOX/user-kubeconfig")"
listing_before="$(ls -a "$SANDBOX/home/.kube")"

run_case "default kubeconfig on a foreign context"
expect_ok
expect_only_call kubectl "kubectl version --client --output=json"
expect_no_output "$foreign_context"

run_case "KUBECONFIG on a foreign context" KUBECONFIG="$SANDBOX/user-kubeconfig"
expect_ok
expect_only_call kubectl "kubectl version --client --output=json"
expect_no_output "${foreign_context}-env"

printf 'not: [a kubeconfig\n' >"$SANDBOX/broken-kubeconfig"
run_case "KUBECONFIG that cannot be read" KUBECONFIG="$SANDBOX/broken-kubeconfig"
expect_ok
expect_only_call kubectl "kubectl version --client --output=json"

begin_check "user's kubeconfig files unchanged"
[ "$(cksum "$SANDBOX/home/.kube/config" "$SANDBOX/user-kubeconfig")" = "$before" ] ||
  fail_case "a kubeconfig of the user was modified"
[ "$(ls -a "$SANDBOX/home/.kube")" = "$listing_before" ] ||
  fail_case "a file was added to or removed from ~/.kube"

finish
