#!/usr/bin/env bash
# Times the steps of task up (spec 001, T088; FR-015; E17).
#
# Usage: bash local/scripts/steps.sh run NAME -- COMMAND [ARG...]
#        bash local/scripts/steps.sh total START
#   run    runs COMMAND, then prints "Step NAME: <n> s." with the whole
#          seconds it took; when COMMAND fails, prints nothing and exits with
#          its status, so that the message of the command stays the last one
#   total  prints "Total: <n> s." for the seconds since START, a time as
#          date +%s gives it, which task up reads once at its start
#
# Nothing here keeps a state: each line stands alone, and the order of the
# lines is the order of the steps. COMMAND is run as given, never through a
# shell string.
set -euo pipefail

die() {
  printf 'steps: %s\n' "$1" >&2
  exit 1
}

case "${1:-}" in
  run)
    [ "$#" -ge 4 ] && [ "${3:-}" = "--" ] || die "usage: bash local/scripts/steps.sh run NAME -- COMMAND [ARG...]"
    name="$2"
    shift 3
    begin="$(date +%s)"
    "$@"
    printf 'Step %s: %s s.\n' "$name" "$(($(date +%s) - begin))"
    ;;
  total)
    [[ ${2:-} =~ ^[0-9]+$ ]] || die "usage: bash local/scripts/steps.sh total START (seconds since the epoch)"
    printf 'Total: %s s.\n' "$(($(date +%s) - $2))"
    ;;
  *) die "usage: bash local/scripts/steps.sh run NAME -- COMMAND [ARG...] | total START" ;;
esac
