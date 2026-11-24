#!/usr/bin/env bash
# Runs the checks of the golden repo that need no cluster: every control
# script of tests/static/, local/tests/static/ and gcp/tests/static/, and
# through them the Rego policies, then the preflight checks of task up in
# local/tests/preflight/, run against simulated binaries, without any
# container engine (contracts/task-cli.md, `task check`). Called by
# `task check`. Exits non-zero when a control fails, and prefixes each
# failure with the identifier of the control and the requirement or
# condition it carries (spec 001, FR-012).
#
# Naming convention of the tests (spec 001, T004):
# - one file per control, named after its identifier in lower case and a
#   short slug: s05-kind-config.sh, p01-versions.sh, e04-secrets-fresh.sh;
# - static controls live in tests/static/ (common layer), local/tests/static/
#   and gcp/tests/static/ (target layers); the preflight checks live in
#   local/tests/preflight/, their simulated binaries in its fakes/ and their
#   shared helpers in its lib/, which this runner does not run; the other
#   kinds of tests live in the folders that tasks.md names, outside this
#   runner;
# - each control script starts with two header lines, read here:
#     # control: S21
#     # carries: FR-010, FR-017; ADR-012, condition 5
# - a Rego policy is policy/<name>.rego (or local/policy/, gcp/policy/), in
#   package <name>, with its tests in <name>_test.rego, same package, rules
#   named test_<control>_<case>. A control script runs it with conftest and
#   names the package; this runner refuses a policy that breaks the rule,
#   because conftest passes without a word on a package that does not exist.
#
# Rule of every shell script of the golden repo (a *.sh file, or a file that
# starts with a shell shebang), checked here: each cd is written
# CDPATH='' cd -- <dir>. With a CDPATH exported, cd prints the directory it
# finds, and "$(cd <dir> && pwd)" returns two lines. The rule holds for every
# cd, not only those in a command substitution: a line does not show whether
# its output is captured (a function called in "$(...)", a subshell in a
# pipe, a substitution over several lines).
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CDPATH='' cd -- "$root"

control_dirs="tests/static local/tests/static gcp/tests/static local/tests/preflight"
policy_dirs="policy local/policy gcp/policy"
ran=0
failed=0

# Value of the "# <key>: <value>" header line of file $2, in its first lines.
header_value() {
  awk -v key="# $1: " \
    'NR > 20 { exit } index($0, key) == 1 { print substr($0, length(key) + 1); exit }' "$2"
}

# Name of the first "package" of Rego file $1.
rego_package() {
  awk '$1 == "package" { print $2; exit }' "$1"
}

# Prints each line read on stdin, prefixed with $1.
prefix_lines() {
  local prefix="$1" line
  while IFS= read -r line || [ -n "$line" ]; do
    printf '%s %s\n' "$prefix" "$line"
  done
}

fail_runner() {
  failed=$((failed + 1))
  printf 'FAIL  RUNNER\n'
  printf '%s\n' "$1" | prefix_lines "[RUNNER | FR-012]"
}

run_control() {
  local script="$1" id carries out status
  id="$(header_value control "$script")"
  carries="$(header_value carries "$script")"
  if [ -z "$id" ] || [ -z "$carries" ]; then
    fail_runner "$script has no '# control:' or '# carries:' header line."
    return 0
  fi
  ran=$((ran + 1))
  if out="$(bash "$script" 2>&1)"; then
    printf 'ok    %-4s %s\n' "$id" "$script"
    return 0
  else
    status=$?
  fi
  failed=$((failed + 1))
  printf 'FAIL  %-4s %s\n' "$id" "$script"
  if [ -z "$out" ]; then
    out="failed with exit code $status and no message"
  fi
  printf '%s\n' "$out" | prefix_lines "[$id | $carries]"
}

# Every policy has its package named after the file, a test file in the same
# package, and a control script that names that package.
check_policy() {
  local policy="$1" name test_file package named_by dir
  name="$(basename "$policy" .rego)"
  test_file="${policy%.rego}_test.rego"
  package="$(rego_package "$policy")"
  if [ "$package" != "$name" ]; then
    fail_runner "$policy declares package '$package'; the convention wants '$name'."
  fi
  if [ ! -f "$test_file" ]; then
    fail_runner "$policy has no test file $test_file."
  elif [ "$(rego_package "$test_file")" != "$name" ]; then
    fail_runner "$test_file is not in package '$name'."
  fi
  named_by=""
  for dir in $control_dirs; do
    [ -d "$dir" ] || continue
    if grep -l -w -e "$name" "$dir"/*.sh >/dev/null 2>&1; then
      named_by="$dir"
    fi
  done
  if [ -z "$named_by" ]; then
    fail_runner "$policy is run by no control script: none names package '$name'."
  fi
}

# Shell scripts of the golden repo, one per line: the *.sh files and the
# files whose first line is a shebang that names a shell. Skips .git and
# node_modules.
shell_scripts() {
  local file first
  find . \( -name .git -o -name node_modules \) -prune -o -type f -print |
    LC_ALL=C sort |
    while IFS= read -r file; do
      case "$file" in
        *.sh)
          printf '%s\n' "$file"
          continue
          ;;
      esac
      first=""
      IFS= read -r first <"$file" || true
      case "$first" in
        '#!'*sh | '#!'*sh' '*) printf '%s\n' "$file" ;;
      esac
    done
}

# One line per cd of shell script $1 that lacks CDPATH='', comments left
# out. The pattern spells c[d] so that this function does not match itself.
unguarded_cd() {
  local script="$1" line
  sed -E -e 's/(^|[[:space:]])#.*$//' \
    -e "s/CDPATH=''[[:space:]]+cd([[:space:]]|\$)/CDPATH_GUARDED\\1/g" "$script" |
    { grep -nE '(^|[[:space:];&|(){}!`])c[d]([[:space:];&|)]|$)' || true; } |
    while IFS=: read -r line _; do
      printf "%s:%s: 'cd' without CDPATH=''. Write CDPATH='' cd -- <dir>: with a CDPATH exported, the directory found is also printed.\n" \
        "$script" "$line"
    done
}

for dir in $control_dirs; do
  [ -d "$dir" ] || continue
  for script in "$dir"/*.sh; do
    [ -f "$script" ] || continue
    run_control "$script"
  done
done

for dir in $policy_dirs; do
  [ -d "$dir" ] || continue
  for policy in "$dir"/*.rego; do
    [ -f "$policy" ] || continue
    case "$policy" in
      *_test.rego) continue ;;
    esac
    check_policy "$policy"
  done
done

cd_problems="$(shell_scripts | while IFS= read -r script; do unguarded_cd "$script"; done)"
if [ -n "$cd_problems" ]; then
  fail_runner "$cd_problems"
fi

if [ "$ran" -eq 0 ]; then
  fail_runner "no control script found in: $control_dirs."
fi

if [ "$failed" -gt 0 ]; then
  printf '%s failure(s); %s control(s) run.\n' "$failed" "$ran" >&2
  exit 1
fi
printf 'All %s control(s) passed.\n' "$ran"
