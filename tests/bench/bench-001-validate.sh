#!/usr/bin/env bash
# BENCH-001, project spec format.
#
# Validates the same minimal project spec in each candidate format, prints the
# error messages for an invalid version, then measures each validation
# (wall-clock time and peak memory) and the size of each tool binary.
#
# Usage: tests/bench/bench-001-validate.sh [runs]
#   runs  measured runs per option, 5 by default, after one warm-up run.
#
# Prerequisites, with the versions pinned below and checked at start:
#   uv (for uv and uvx), cue, pkl, score-compose, git and /usr/bin/time.
# Network: the first run lets uvx fetch check-jsonschema, its dependencies
# (resolved as of EXCLUDE_NEWER) and, if missing, the pinned Python. The Score
# JSON Schema is a local copy (bench-001/vendor/score-spec), checked by hash.
set -euo pipefail

readonly CHECK_JSONSCHEMA_VERSION="0.39.0"
readonly PYTHON_VERSION="3.13.15"
readonly EXCLUDE_NEWER="2026-11-19"
readonly CUE_VERSION="0.17.1"
readonly PKL_VERSION="0.33.1"
readonly SCORE_COMPOSE_VERSION="0.50.0"
# Git blob of score-v1b1.json at tag 0.4.1 of score-spec/spec.
readonly SCORE_SCHEMA_BLOB="9acd54435984be59d653fb73b37980713d9b4d1e"

ROOT="$(CDPATH='' cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bench-001"
readonly ROOT
readonly SCORE_SCHEMA="$ROOT/vendor/score-spec/score-v1b1.json"
readonly RUNS="${1:-5}"

WORK="$(mktemp -d)"
readonly WORK
trap 'rm -rf "$WORK"' EXIT

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

# run <command...>: runs the command directly, or under /usr/bin/time when
# TIME_REPORT names a report file (set by timed below).
TIME_REPORT=""
run() {
  if [ -z "$TIME_REPORT" ]; then
    "$@"
  elif [ "$(uname -s)" = Darwin ]; then
    /usr/bin/time -l -o "$TIME_REPORT" "$@"
  else
    /usr/bin/time -f '%M' -o "$TIME_REPORT" "$@"
  fi
}

# now_ns: wall clock in nanoseconds. /usr/bin/time only gives 10 ms steps,
# too coarse for tools that answer in a few milliseconds.
now_ns() {
  local t
  t="$(date +%s%N)"
  case "$t" in
  *[!0-9]*) perl -MTime::HiRes=time -e 'printf "%d\n", time * 1e9' ;;
  *) printf '%s\n' "$t" ;;
  esac
}

# peak_mib <report file>: peak resident memory from the /usr/bin/time report.
peak_mib() {
  if [ "$(uname -s)" = Darwin ]; then
    awk '/maximum resident set size/{printf "%.1f\n", $1 / 1048576}' "$1"
  else
    awk '{printf "%.1f\n", $1 / 1024}' "$1"
  fi
}

check_jsonschema() {
  run uvx --quiet --python "$PYTHON_VERSION" --exclude-newer "$EXCLUDE_NEWER" \
    --from "check-jsonschema==${CHECK_JSONSCHEMA_VERSION}" check-jsonschema "$@"
}

# Prints the packages uv resolves for check-jsonschema with the same Python
# and cut-off date as check_jsonschema above. Resolution only, no install.
print_resolved_packages() {
  printf 'check-jsonschema==%s\n' "$CHECK_JSONSCHEMA_VERSION" |
    uv pip compile - --quiet --no-header --no-annotate \
      --python-version "$PYTHON_VERSION" --exclude-newer "$EXCLUDE_NEWER"
}

# One function per option. Each takes the spec file to validate.
validate_a_jsonschema() {
  check_jsonschema --schemafile "$ROOT/jsonschema/spec.schema.json" "$1"
}

validate_b_cue() {
  run cue vet -c -d '#Spec' "$ROOT/cue/spec.cue" "$1"
}

validate_c_pkl() {
  run pkl eval --format yaml "$1"
}

validate_c_pkl_yaml() {
  run pkl eval -p "input=$1" "$ROOT/pkl/yaml-check.pkl"
}

validate_d1_score_schema() {
  check_jsonschema --schemafile "$SCORE_SCHEMA" "$1"
}

# score-compose has no validate-only command: generate validates, provisions
# the resources and writes a compose file, all inside the temporary folder.
validate_d1_score_compose() {
  (cd "$WORK/score-compose" &&
    run score-compose generate --quiet --image example/api:0.1.0 \
      --output "$WORK/score-compose/compose.yaml" "$1")
}

validate_d2_score_section() {
  check_jsonschema --schemafile "$ROOT/score-section/spec.schema.json" "$1"
}

# Baseline for option A: start of uvx and of check-jsonschema, no validation.
baseline_check_jsonschema() {
  check_jsonschema --version
}

check_prerequisites() {
  local tool
  for tool in uv uvx cue pkl score-compose git; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"
  done
  [ -x /usr/bin/time ] || die "/usr/bin/time is missing (package 'time' on Linux)"
  [ "$(git hash-object "$SCORE_SCHEMA")" = "$SCORE_SCHEMA_BLOB" ] ||
    die "$SCORE_SCHEMA differs from score-spec/spec 0.4.1"

  cue version | head -n 1 | grep -qx "cue version v${CUE_VERSION}" ||
    die "cue ${CUE_VERSION} expected, got: $(cue version | head -n 1)"
  [ "$(pkl --version | awk '{print $2}')" = "$PKL_VERSION" ] ||
    die "pkl ${PKL_VERSION} expected, got: $(pkl --version)"
  [ "$(score-compose --version | head -n 1 | awk '{print $2}')" = "$SCORE_COMPOSE_VERSION" ] ||
    die "score-compose ${SCORE_COMPOSE_VERSION} expected, got: $(score-compose --version | head -n 1)"
  check_jsonschema --version | grep -q "version ${CHECK_JSONSCHEMA_VERSION}$" ||
    die "check-jsonschema ${CHECK_JSONSCHEMA_VERSION} expected"

  mkdir -p "$WORK/score-compose"
  (cd "$WORK/score-compose" && score-compose init --quiet --no-sample)
}

# expect <ok|fail> <label> <command...>: runs the command, shows its output and
# stops the script if the exit status is not the expected one.
expect() {
  local want="$1" label="$2" status=0
  shift 2
  printf '\n--- %s (expected: %s)\n' "$label" "$want"
  "$@" 2>&1 || status=$?
  printf -- '--- exit status: %s\n' "$status"
  if [ "$want" = ok ] && [ "$status" -ne 0 ]; then
    die "$label: expected success"
  fi
  if [ "$want" = fail ] && [ "$status" -eq 0 ]; then
    die "$label: expected a validation error"
  fi
}

run_functional_checks() {
  printf '\n== 1. Valid and invalid spec in each format\n'
  expect ok "A JSON Schema, valid" validate_a_jsonschema "$ROOT/yaml/valid.yaml"
  expect fail "A JSON Schema, invalid" validate_a_jsonschema "$ROOT/yaml/invalid.yaml"
  expect ok "B CUE, valid" validate_b_cue "$ROOT/yaml/valid.yaml"
  expect fail "B CUE, invalid" validate_b_cue "$ROOT/yaml/invalid.yaml"
  expect ok "C Pkl, valid" validate_c_pkl "$ROOT/pkl/valid.pkl"
  expect fail "C Pkl, invalid" validate_c_pkl "$ROOT/pkl/invalid.pkl"
  expect ok "C Pkl reading YAML, valid" validate_c_pkl_yaml "$ROOT/yaml/valid.yaml"
  expect fail "C Pkl reading YAML, invalid" validate_c_pkl_yaml "$ROOT/yaml/invalid.yaml"
  expect ok "D1 Score schema, valid" validate_d1_score_schema "$ROOT/score/valid.score.yaml"
  expect fail "D1 Score schema, invalid" validate_d1_score_schema "$ROOT/score/invalid.score.yaml"
  expect ok "D1 score-compose, valid" validate_d1_score_compose "$ROOT/score/valid.score.yaml"
  expect fail "D1 score-compose, invalid" validate_d1_score_compose "$ROOT/score/invalid.score.yaml"
  expect ok "D2 Score section, valid" validate_d2_score_section "$ROOT/score-section/valid.yaml"
  expect fail "D2 Score section, invalid" validate_d2_score_section "$ROOT/score-section/invalid.yaml"
}

# timed <report file> <validate function> <spec file>: runs the validation
# with its tool under /usr/bin/time and prints "<milliseconds> <peak MiB>".
# The wall time includes the start of /usr/bin/time itself.
timed() {
  local report="$1" status=0 start end
  shift
  TIME_REPORT="$report"
  start="$(now_ns)"
  "$@" >/dev/null 2>&1 || status=$?
  end="$(now_ns)"
  TIME_REPORT=""
  [ "$status" -eq 0 ] || return "$status"
  printf '%s %s\n' "$(awk -v us="$(((end - start) / 1000))" 'BEGIN{printf "%.1f", us / 1000}')" \
    "$(peak_mib "$report")"
}

# measure <label> <command...>: one warm-up run, then RUNS measured runs.
measure() {
  local label="$1" i result
  shift
  "$@" >/dev/null 2>&1 || die "$label: warm-up run failed"
  for i in $(seq 1 "$RUNS"); do
    result="$(timed "$WORK/time.txt" "$@")" || die "$label: run $i failed"
    printf '%s\t%s\t%s\n' "$label" "$i" "${result// /$'\t'}" >>"$WORK/results.tsv"
    printf '%-28s run %s: %s ms, %s MiB\n' "$label" "$i" "${result% *}" "${result#* }"
  done
}

# median_and_range <label> <column>: column 3 is milliseconds, column 4 is MiB.
median_and_range() {
  awk -F'\t' -v l="$1" -v c="$2" '$1 == l {print $c}' "$WORK/results.tsv" |
    sort -n |
    awk '{v[NR] = $1}
      END {
        m = (NR % 2) ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2
        printf "%.1f (range %.1f)", m, v[NR] - v[1]
      }'
}

run_measures() {
  printf '\n== 2. Validation of the valid spec, %s runs per option\n' "$RUNS"
  : >"$WORK/results.tsv"
  measure "A0 baseline, --version" baseline_check_jsonschema
  measure "A check-jsonschema" validate_a_jsonschema "$ROOT/yaml/valid.yaml"
  measure "B cue vet" validate_b_cue "$ROOT/yaml/valid.yaml"
  measure "C pkl eval" validate_c_pkl "$ROOT/pkl/valid.pkl"
  measure "C pkl eval (YAML input)" validate_c_pkl_yaml "$ROOT/yaml/valid.yaml"
  measure "D1 check-jsonschema" validate_d1_score_schema "$ROOT/score/valid.score.yaml"
  measure "D1 score-compose generate" validate_d1_score_compose "$ROOT/score/valid.score.yaml"
  measure "D2 check-jsonschema" validate_d2_score_section "$ROOT/score-section/valid.yaml"

  printf '\n== 3. Medians\n'
  local label
  cut -f1 "$WORK/results.tsv" | uniq | while IFS= read -r label; do
    printf '%-28s time %s ms, memory %s MiB\n' "$label" \
      "$(median_and_range "$label" 3)" "$(median_and_range "$label" 4)"
  done

  printf '\n== 4. Binary size\n'
  local tool
  for tool in cue pkl score-compose; do
    printf '%-14s %s KiB\n' "$tool" "$(du -kL "$(command -v "$tool")" | cut -f1)"
  done
  printf '%-14s %s\n' "check-jsonschema" "Python environment managed by uvx, not measured here"
}

main() {
  case "$RUNS" in
  '' | *[!0-9]* | 0) die "runs must be a positive integer, got '$RUNS'" ;;
  esac
  check_prerequisites
  printf 'Versions: check-jsonschema %s, cue %s, pkl %s, score-compose %s\n' \
    "$CHECK_JSONSCHEMA_VERSION" "$CUE_VERSION" "$PKL_VERSION" "$SCORE_COMPOSE_VERSION"
  printf 'Python %s, packages uploaded before %s, resolved as:\n' \
    "$PYTHON_VERSION" "$EXCLUDE_NEWER"
  print_resolved_packages | sed 's/^/  /'
  printf 'Machine: %s %s\n' "$(uname -s)" "$(uname -m)"
  run_functional_checks
  run_measures
}

main "$@"
