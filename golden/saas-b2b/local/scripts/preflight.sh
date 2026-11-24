#!/usr/bin/env bash
# Preflight checks of `task up` (spec 001, contracts/task-cli.md), run before
# anything is created: docker reaches a local engine that answers, versions,
# memory and profile, host ports. The checks, their order and their sources
# are in lib/preflight-checks.sh.
#
# Usage: bash local/scripts/preflight.sh [PORT...]
#   PORT     a host port that the cluster will publish on 127.0.0.1; the
#            tasks pass the real ones from step 7 (T059)
#   PROFILE  environment, optional: lite or standard forces the profile,
#            under the same memory checks
# Announces the docker context and the profile retained. A refusal is one
# sentence that says what is missing and what to do, on stderr, with exit
# status 1.
#
# This file loads the checks and runs them, with no condition: sourced
# instead of run, it still checks, and a refusal ends the shell that sourced
# it. The tests that replace the TCP probe source the library instead
# (local/tests/preflight/lib/harness.sh).
set -euo pipefail

here="${BASH_SOURCE[0]}"
case "$here" in
  */*) here="${here%/*}" ;;
  *) here="." ;;
esac
# shellcheck disable=SC1091 # lib/preflight-checks.sh is checked on its own
. "$here/lib/preflight-checks.sh"
main "$@"
