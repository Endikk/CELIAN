#!/usr/bin/env bash
# control: E19
# carries: FR-019; ADR-004, condition 9; constitution, principle IX; research RS-21
#
# After task up, the kubeconfig of the project, which reads every Secret of
# the cluster, is outside the repository, or at least ignored by Git
# (ADR-004, condition 9). It is readable by its owner alone, names the
# context of the local cluster, and no kubeconfig file appears in the tree
# of the golden repo.
set -uo pipefail
# shellcheck disable=SC1091 # lib/e2e.sh is checked on its own
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/e2e.sh"

must_succeed up || e2e_finish

if [ ! -f "$E2E_KUBECONFIG" ]; then
  fail "no kubeconfig at $E2E_KUBECONFIG after task up"
  e2e_finish
fi

case "$E2E_KUBECONFIG" in
  "$E2E_ROOT"/*)
    if ! git -C "$E2E_ROOT" check-ignore -q -- "$E2E_KUBECONFIG"; then
      fail "the kubeconfig $E2E_KUBECONFIG is inside the repository and not ignored by Git"
    fi
    ;;
esac

if mode="$(stat -c '%a' "$E2E_KUBECONFIG" 2>/dev/null)"; then
  :
else
  mode="$(stat -f '%Lp' "$E2E_KUBECONFIG")"
fi
if [ "$mode" != 600 ]; then
  fail "the kubeconfig $E2E_KUBECONFIG has mode $mode; 600 expected, readable by its owner alone"
fi

contexts="$(kubectl --kubeconfig "$E2E_KUBECONFIG" config get-contexts --output=name 2>&1)"
if ! printf '%s\n' "$contexts" | grep -qx "$E2E_CONTEXT"; then
  fail "the kubeconfig of the project has no context $E2E_CONTEXT: $contexts"
fi

left="$(find "$E2E_ROOT" \( -name .git -o -name node_modules \) -prune -o \
  -type f \( -name 'kubeconfig*' -o -name '*.kubeconfig' -o -name "kind-$E2E_CLUSTER" \) -print)"
if [ -n "$left" ]; then
  fail "kubeconfig files in the tree of the golden repo: $left"
fi

e2e_finish
