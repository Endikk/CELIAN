#!/usr/bin/env bash
# control: E21
# carries: FR-004, FR-017; ADR-012, condition 3; contracts/secrets.md
#
# The volume of the database never lives without its Secrets (ADR-012,
# condition 3): after task up, E21 removes the Secret db-auth and keeps the
# volume, the PVC data-postgres-0. task up then stops: it names the volume
# and the missing Secret, proposes to remove both together (task down), and
# creates nothing, db-auth above all. Then E21 runs task down, which removes
# the cluster with both, so that the next test starts from a new one.
set -uo pipefail
# shellcheck disable=SC1091 # lib/e2e.sh is checked on its own
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/e2e.sh"

must_succeed up || e2e_finish
if ! kube_e2e -n "$E2E_APP_NAMESPACE" get pvc "$E2E_DATA_VOLUME" >/dev/null 2>&1; then
  fail "no volume $E2E_DATA_VOLUME after task up"
  e2e_finish
fi
if ! kube_e2e -n "$E2E_APP_NAMESPACE" delete secret db-auth >/dev/null; then
  fail "could not remove the Secret db-auth"
  e2e_finish
fi

run_task up
if [ "$STATUS" -eq 0 ]; then
  fail "task up succeeded with the volume of the database and without db-auth"
  show_output
fi
expect_output "$E2E_DATA_VOLUME"
expect_output "db-auth"
expect_output "task down"
expect_output "Nothing was created"
if kube_e2e -n "$E2E_APP_NAMESPACE" get secret db-auth >/dev/null 2>&1; then
  fail "task up created db-auth again, beside a volume that the old password opens"
fi
kube_e2e -n "$E2E_APP_NAMESPACE" get pvc "$E2E_DATA_VOLUME" >/dev/null 2>&1 ||
  fail "task up removed the volume $E2E_DATA_VOLUME"

must_succeed down

e2e_finish
