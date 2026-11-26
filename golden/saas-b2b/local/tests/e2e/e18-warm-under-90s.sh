#!/usr/bin/env bash
# control: E18
# carries: FR-015; plan, "Critères de succès"
#
# A warm start, on a cluster that is kept, takes under 90 seconds (spec 001,
# T085): the images of the API and the front come from the cache of the
# build and from kind load, the others are already on the node, the
# Secrets and the data stay. The test runs task up once to be sure that the
# environment stands, then times a second one.
set -uo pipefail
# shellcheck disable=SC1091 # lib/e2e.sh is checked on its own
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/e2e.sh"

readonly WARM_LIMIT_SECONDS=90

must_succeed up || e2e_finish

start="$SECONDS"
must_succeed up || e2e_finish
elapsed=$((SECONDS - start))
printf 'note: a warm task up took %s s (limit %s s).\n' "$elapsed" "$WARM_LIMIT_SECONDS"
if [ "$elapsed" -ge "$WARM_LIMIT_SECONDS" ]; then
  fail "a warm task up took $elapsed s, $WARM_LIMIT_SECONDS s at most (FR-015)"
  show_output
fi

e2e_finish
