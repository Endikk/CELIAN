#!/usr/bin/env bash
# control: S15
# carries: FR-011, FR-012; ADR-008, conditions 1 to 6 and 8, question 1; ADR-007, condition 2; ADR-010; ADR-015, conditions 7, 13, 15, 16 and 18; R-32; R-05, R-17, R-18; research RS-16 (registry of the providers)
#
# Two parts, both on the HCL of the two roots, gcp/tofu/ and the budget root
# gcp/budget/ (T110), without any credential:
# - policy: the tests of the conftest packages of gcp/policy/, then each
#   failing case of gcp/policy/testdata/, which must be refused with the
#   message its "# expect:" line gives (a "# with:" line names a file of the
#   repository that the case is read together with), then the packages on the
#   roots. tofu_budget reads both roots at once: the alert, and the identity
#   of the main root that must not hold a budget role;
# - scan: Trivy on the root, with the checks embedded in its binary. Each
#   finding is fixed, or justified in writing right above its resource with a
#   "#trivy:ignore:<ID>" comment (T109), and only the closed list of this
#   script, allowed_ignores, may carry one. No .trivyignore file and no
#   trivy.yaml is read. Nothing is sent to Aqua: with the telemetry and the
#   version check both off, Trivy sends no request to check.trivy.dev, and
#   no checks bundle is fetched (research RS-22). A copy of the root with the
#   Cloud SQL logging flags off must fail on the five checks they answer.
#
# Usage: gcp/tests/static/s15-tofu-policy.sh [policy|scan]
# Without argument, both parts: that is how `task check` runs it, through
# tests/run-static.sh. `task gcp:policy` and `task gcp:scan` run one each.
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
CDPATH='' cd -- "$root"

part="${1:-both}"
dir="gcp/tofu"
budget_dir="gcp/budget"
policies="gcp/policy"
packages="tofu_adr008 tofu_secret_sync tofu_config_sync tofu_finops tofu_memorystore tofu_sql_tls"
# Run on the two roots together, so it is not in the list above.
budget_package="tofu_budget"
# Run on each root alone, the budget root included: the registry of the
# providers is written in both (research RS-16).
registry_package="tofu_registry"
problems=0

# The closed list of Trivy ignore comments: "<comment line>|<resource>". A
# comment that is not here, in this exact form, right above this resource, is
# refused. Adding one takes a review by [SECU], and a justification written
# above the comment (research RS-22).
allowed_ignores=(
  "#trivy:ignore:AVD-GCP-0061|google_container_cluster.main"
)

case "$part" in
  policy | scan | both) ;;
  *)
    echo "usage: gcp/tests/static/s15-tofu-policy.sh [policy|scan]" >&2
    exit 1
    ;;
esac

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is not installed: run tests/tools/install.sh <dir>, then put <dir> on PATH." >&2
    exit 1
  fi
}

# Value of the "# <key>: <value>" line of file $2, in its first lines.
header_value() {
  awk -v key="# $1: " \
    'NR > 10 { exit } index($0, key) == 1 { print substr($0, length(key) + 1); exit }' "$2"
}

# True when root $1 has its .tf files; says what is missing otherwise.
root_present() {
  set -- "$1"/*.tf
  if [ ! -f "$1" ]; then
    echo "${1%/*} holds no .tf file: an OpenTofu root of the gcp layer is missing (T106 to T108 for gcp/tofu, T110 for gcp/budget)." >&2
    problems=$((problems + 1))
    return 1
  fi
}


# Each failing case is refused, by a message that holds its "# expect:" text.
check_cases() {
  local case_file package expect with out found=0
  for case_file in "$policies"/testdata/*.tf; do
    [ -f "$case_file" ] || continue
    found=$((found + 1))
    package="$(header_value package "$case_file")"
    expect="$(header_value expect "$case_file")"
    # Optional: a file of the repository, read together with the case.
    with="$(header_value with "$case_file")"
    if [ -z "$package" ] || [ -z "$expect" ]; then
      echo "$case_file: no '# package:' or '# expect:' line." >&2
      problems=$((problems + 1))
      continue
    fi
    if [ -n "$with" ] && [ ! -f "$with" ]; then
      echo "$case_file: the '# with:' file $with does not exist." >&2
      problems=$((problems + 1))
      continue
    fi
    # $with is a path without spaces, or empty: left unquoted on purpose.
    # shellcheck disable=SC2086
    if out="$(conftest test --no-color --combine --policy "$policies" --namespace "$package" "$case_file" $with platform.yaml 2>&1)"; then
      echo "$case_file: accepted by $package, yet it is a failing case: $expect" >&2
      problems=$((problems + 1))
    elif ! printf '%s\n' "$out" | grep -F -q -e "$expect"; then
      echo "$case_file: refused by $package, but no message holds: $expect" >&2
      printf '%s\n' "$out" >&2
      problems=$((problems + 1))
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo "$policies/testdata holds no failing case." >&2
    problems=$((problems + 1))
  fi
}

run_policy() {
  local package main_present budget_present
  need conftest
  # One package per run: conftest says nothing about a package it does not
  # find (research RS-18), and tests/run-static.sh refuses a policy that no
  # control script names.
  for package in $packages $budget_package $registry_package; do
    conftest verify --no-color --policy "$policies" --namespace "$package" || problems=$((problems + 1))
  done
  check_cases
  main_present=0
  budget_present=0
  if root_present "$dir"; then main_present=1; fi
  if root_present "$budget_dir"; then budget_present=1; fi
  if [ "$main_present" -eq 1 ]; then
    for package in $packages; do
      conftest test --no-color --combine --policy "$policies" --namespace "$package" "$dir"/*.tf platform.yaml ||
        problems=$((problems + 1))
    done
  fi
  if [ "$main_present" -eq 1 ]; then
    conftest test --no-color --combine --policy "$policies" --namespace "$registry_package" \
      "$dir"/*.tf || problems=$((problems + 1))
  fi
  if [ "$budget_present" -eq 1 ]; then
    conftest test --no-color --combine --policy "$policies" --namespace "$registry_package" \
      "$budget_dir"/*.tf || problems=$((problems + 1))
  fi
  # The budget policy reads both roots: the alert, and the identity of the
  # main root, which must not hold a role that writes budgets.
  if [ "$main_present" -eq 1 ] && [ "$budget_present" -eq 1 ]; then
    conftest test --no-color --combine --policy "$policies" --namespace "$budget_package" \
      "$budget_dir"/*.tf "$dir"/*.tf || problems=$((problems + 1))
  fi
}

# Trivy in an emptied environment, with its cache in a temporary directory.
# $1 is the scratch directory, $2 the directory to scan.
# - --config '' : no trivy.yaml, so that a file of the repository cannot
#   silence the scan; --ignorefile '' : no .trivyignore;
# - --disable-telemetry and --skip-version-check : both off, Trivy sends no
#   request to check.trivy.dev (pkg/notification/notice.go at v0.76.2);
# - --skip-check-update : the checks embedded in the binary, so that the
#   result follows the version that install.sh verified (decision of the DSI,
#   research RS-22); Renovate brings new rules with each Trivy version.
trivy_scan() {
  env -i PATH="$PATH" HOME="$1/home" trivy config --quiet --config '' \
    --cache-dir "$1/cache" --disable-telemetry --skip-version-check \
    --skip-check-update --ignorefile '' \
    --misconfig-scanners terraform --exit-code 1 "$2"
}

# The comments that Trivy reads as a rule in the files given as arguments:
# one "<file>:<line>: <comment>|<resource>" for each that is not in the closed
# list. Trivy takes any word that starts with "trivy:" or "tfsec:" (after
# "#", "/" or "*") as a rule, so the test is on that word, and the comment
# must be the whole line, right above its resource (v0.76.2, pkg/iac/ignore).
ignore_findings() {
  local file entry where claimed allowed known
  for file in "$@"; do
    [ -f "$file" ] || continue
    while IFS= read -r entry; do
      [ -n "$entry" ] || continue
      where="${entry%%: *}"
      claimed="${entry#*: }"
      known=0
      for allowed in "${allowed_ignores[@]}"; do
        if [ "$claimed" = "$allowed" ]; then
          known=1
        fi
      done
      if [ "$known" -eq 0 ]; then
        printf '%s: ignore comment outside the closed list (%s); only allowed_ignores of gcp/tests/static/s15-tofu-policy.sh may silence Trivy\n' "$where" "$claimed"
      fi
    done < <(awk '
      function trim(s) {
        sub(/^[ \t]+/, "", s)
        sub(/[ \t]+$/, "", s)
        return s
      }
      function flush(address) {
        print FILENAME ":" pending_line ": " pending "|" address
        pending = ""
      }
      {
        line = trim($0)
        if (line ~ /(^|[ \t#\/*])(tfsec|trivy):/) {
          if (pending != "") { flush("") }
          pending = line
          pending_line = FNR
          next
        }
        if (pending != "" && line != "" && line !~ /^(#|\/\/)/) {
          address = ""
          if (match(line, /^resource[ \t]+"[^"]+"[ \t]+"[^"]+"/)) {
            address = substr(line, RSTART, RLENGTH)
            sub(/^resource[ \t]+"/, "", address)
            sub(/"[ \t]+"/, ".", address)
            sub(/"$/, "", address)
          }
          flush(address)
        }
      }
      END { if (pending != "") { flush("") } }
    ' "$file")
  done
}

# Each failing case of testdata/ignores/ must be refused, with the message
# its "# expect:" line gives.
check_ignore_cases() {
  local case_file expect out found=0
  for case_file in "$policies"/testdata/ignores/*.tf; do
    [ -f "$case_file" ] || continue
    found=$((found + 1))
    expect="$(header_value expect "$case_file")"
    out="$(ignore_findings "$case_file")"
    if [ -z "$out" ]; then
      echo "$case_file: its ignore comment is accepted, yet it is a failing case: $expect" >&2
      problems=$((problems + 1))
    elif ! printf '%s\n' "$out" | grep -F -q -e "$expect"; then
      echo "$case_file: refused, but no message holds: $expect" >&2
      printf '%s\n' "$out" >&2
      problems=$((problems + 1))
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo "$policies/testdata/ignores holds no failing case." >&2
    problems=$((problems + 1))
  fi
}

# Proof that Trivy applies the Cloud SQL logging checks to the root: in a
# copy where each flag is turned off, it must fail on all five. A value that
# Trivy cannot resolve (a computed database_version) makes it pass in silence.
check_scan_applies_checks() {
  local work="$1" copy out id
  copy="$work/copy"
  mkdir -p "$copy/gcp/tofu"
  cp "$dir"/*.tf "$copy/gcp/tofu/"
  cp platform.yaml "$copy/platform.yaml"
  awk '
    /^[ \t]*name[ \t]*=[ \t]*"log_(connections|disconnections|checkpoints|lock_waits)"/ { off = "\"off\""; armed = 1 }
    /^[ \t]*name[ \t]*=[ \t]*"log_temp_files"/ { off = "\"-1\""; armed = 1 }
    armed && /^[ \t]*value[ \t]*=/ { sub(/"[^"]*"/, off); armed = 0 }
    { print }
  ' "$dir/database.tf" >"$copy/gcp/tofu/database.tf"
  if out="$(trivy_scan "$work" "$copy/gcp/tofu" 2>&1)"; then
    echo "Trivy accepted a copy of $dir with its Cloud SQL logging flags off: it does not apply those checks." >&2
    problems=$((problems + 1))
    return 0
  fi
  for id in GCP-0014 GCP-0016 GCP-0020 GCP-0022 GCP-0025; do
    if ! printf '%s\n' "$out" | grep -F -q -e "$id ("; then
      echo "Trivy did not report AVD-$id on a copy of $dir with its Cloud SQL logging flags off: it does not apply that check." >&2
      problems=$((problems + 1))
    fi
  done
}

# Trivy in an emptied environment. Its cache is a temporary directory.
run_scan() {
  local work out scanned root_dir main_present=0
  need trivy
  scanned=()
  if root_present "$dir"; then
    main_present=1
    scanned+=("$dir")
  fi
  if root_present "$budget_dir"; then
    scanned+=("$budget_dir")
  fi
  if [ "${#scanned[@]}" -eq 0 ]; then
    return 0
  fi
  work="$(mktemp -d)"
  mkdir -p "$work/home"
  for root_dir in "${scanned[@]}"; do
    if ! trivy_scan "$work" "$root_dir"; then
      echo "Trivy refuses $root_dir: fix each finding, or justify it right above its resource (T109, T110)." >&2
      problems=$((problems + 1))
    fi
    out="$(ignore_findings "$root_dir"/*.tf "$root_dir"/*.tf.json "$root_dir"/*.tfvars "$root_dir"/*.tfvars.json)"
    if [ -n "$out" ]; then
      printf '%s\n' "$out" >&2
      problems=$((problems + 1))
    fi
  done
  # The proof that Trivy applies the Cloud SQL checks is on the main root.
  if [ "$main_present" -eq 1 ]; then
    check_scan_applies_checks "$work"
  fi
  check_ignore_cases
  rm -rf "$work"
}

case "$part" in
  policy) run_policy ;;
  scan) run_scan ;;
  both)
    run_policy
    run_scan
    ;;
esac

if [ "$problems" -gt 0 ]; then
  exit 1
fi
