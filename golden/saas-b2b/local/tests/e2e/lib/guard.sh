# shellcheck shell=bash
# The guard of local/tests/e2e/run.sh. Sourced, never run on its own.
#
# The tests on kind use the names of the development environment, and they
# remove what they find: one reuses a cluster that exists, the cleanup of
# run.sh runs task down, E08 runs task mirror:purge. task test:e2e therefore
# never starts over a cluster, a mirror container or a mirror volume of those
# names: it would remove what it did not create. The names are written here
# on purpose, apart from local/scripts/lib/local-env.sh, as in lib/e2e.sh: a
# change of name there must break a test, not move it along. A CI runner is
# new and has none of them.

E2E_GUARD_CLUSTER="saas-b2b"
E2E_GUARD_MIRROR="saas-b2b-mirror"
E2E_GUARD_VOLUME="saas-b2b-mirror"

# e2e_guard: returns 0 when none of the three exists. Otherwise prints what
# exists, and what to do, on stderr, and returns 1. It returns 1 too when it
# cannot tell: kind get clusters fails when the engine does not answer, and
# the inspections below then say nothing true either. It creates and removes
# nothing.
e2e_guard() {
  local clusters found=""
  if ! clusters="$(kind get clusters 2>/dev/null)"; then
    printf 'task test:e2e: cannot check whether the environment of the project exists (kind get clusters failed): check the container engine, then run it again. Nothing was started.\n' >&2
    return 1
  fi
  if printf '%s\n' "$clusters" | grep -qx -- "$E2E_GUARD_CLUSTER"; then
    found="$found  - cluster $E2E_GUARD_CLUSTER"$'\n'
  fi
  if docker container inspect --format '{{.Name}}' "$E2E_GUARD_MIRROR" >/dev/null 2>&1; then
    found="$found  - container $E2E_GUARD_MIRROR"$'\n'
  fi
  if docker volume inspect --format '{{.Name}}' "$E2E_GUARD_VOLUME" >/dev/null 2>&1; then
    found="$found  - volume $E2E_GUARD_VOLUME"$'\n'
  fi
  [ -z "$found" ] && return 0
  printf 'task test:e2e refuses to start: these already exist on this machine, under the names that the tests create and remove:\n%s' "$found" >&2
  printf 'It would take your development environment for its own and remove it. Nothing was started or removed.\nRun it on a machine without them (the CI runner is one), or hand them over yourself with task down and task mirror:purge.\n' >&2
  return 1
}
