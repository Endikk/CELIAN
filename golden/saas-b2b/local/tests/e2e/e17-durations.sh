#!/usr/bin/env bash
# control: E17
# carries: FR-015; contracts/task-cli.md (task up, "Sortie en cas de succès")
#
# task up shows how long each step took, how long it took in all, and the
# size of the mirror volume (spec 001, T085):
# - one line "Step <name>: <n> s." for each step of task up, in the order of
#   the plan (plan, "Ce que fait task up"), n a whole number;
# - one line "Total: <n> s.", at least the sum of the steps, which are
#   timed one by one;
# - a line that names the mirror volume and gives its size, as
#   "Mirror volume saas-b2b-mirror: 1.2GB.".
# The test runs task up on the environment that stands: the steps are the
# same on a kept cluster, only shorter.
set -uo pipefail
# shellcheck disable=SC1091 # lib/e2e.sh is checked on its own
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/e2e.sh"

readonly STEPS="preflight cluster mirror secrets platform images application database cache ready"

must_succeed up || e2e_finish

sum=0
previous=0
for step in $STEPS; do
  line="$(printf '%s\n' "$OUTPUT" | grep -E "^Step $step: [0-9]+ s\.$" | head -n 1)"
  if [ -z "$line" ]; then
    fail "the output of task up has no line \"Step $step: <n> s.\""
    continue
  fi
  position="$(printf '%s\n' "$OUTPUT" | grep -n -E "^Step $step: " | head -n 1 | cut -d: -f1)"
  if [ "$position" -le "$previous" ]; then
    fail "the step $step is not shown in the order of the plan"
  fi
  previous="$position"
  seconds="${line#Step "$step": }"
  seconds="${seconds% s.}"
  sum=$((sum + seconds))
done

total_line="$(printf '%s\n' "$OUTPUT" | grep -E '^Total: [0-9]+ s\.$' | head -n 1)"
if [ -z "$total_line" ]; then
  fail "the output of task up has no line \"Total: <n> s.\""
else
  total="${total_line#Total: }"
  total="${total% s.}"
  [ "$total" -ge "$sum" ] || fail "the total of $total s is below the sum of the steps, $sum s"
  [ "$total_line" = "$(printf '%s\n' "$OUTPUT" | grep -E '^Total: ' | tail -n 1)" ] || fail "the total is not the last duration shown"
fi

if ! printf '%s\n' "$OUTPUT" | grep -qE "^Mirror volume $E2E_VOLUME: [0-9.]+ ?[kKMGT]?B\.$"; then
  fail "the output of task up does not give the size of the mirror volume as \"Mirror volume $E2E_VOLUME: <size>.\""
  show_output
fi

e2e_finish
