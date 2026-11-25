#!/usr/bin/env bash
# control: S17
# carries: FR-011, FR-013; constitution, principle X
#
# CI workflows run no OpenTofu plan, apply or destroy, hold no cloud
# credential, publish no plan, and pin every action by a full commit SHA.
# Without argument, checks the workflows of the golden repo, the CI of the
# generated project (T094), and there must be at least one. When the golden
# repo sits in CELIAN, at golden/saas-b2b/, it also checks the CELIAN
# workflow that runs it (research RS-17); a standalone copy (X01) has no
# such workflow. Arguments, if given, replace the default list.
#
# T105 adds what a workflow calls: the Taskfiles, and the shell scripts of the
# gcp layer, where the OpenTofu commands live. They get the rules of
# principle X (no plan, apply or destroy, no Google credential, no published
# plan); the rules on secrets, OIDC tokens and pins are for workflows only.
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

problems=0
default_run=0

report() {
  problems=$((problems + 1))
  printf '%s:%s: %s\n' "$1" "$2" "$3"
}

if [ "$#" -eq 0 ]; then
  default_run=1
  for file in "$root"/.github/workflows/*.yml "$root"/.github/workflows/*.yaml; do
    if [ -f "$file" ]; then
      set -- "$@" "$file"
    fi
  done
  if [ "$#" -eq 0 ]; then
    report "$root/.github/workflows" 0 "no workflow found: the generated project has no CI (FR-013)"
  fi
  celian_root="$(CDPATH='' cd -- "$root/../.." && pwd)"
  if [ "$celian_root/golden/saas-b2b" = "$root" ] && [ -d "$celian_root/.github/workflows" ]; then
    set -- "$@" "$celian_root/.github/workflows/golden-saas-b2b.yml"
  fi
  for file in "$root"/Taskfile.yml "$root"/local/tasks/*.yml "$root"/gcp/tasks/*.yml \
    "$root"/gcp/tests/static/*.sh "$root"/gcp/scripts/*.sh; do
    if [ -f "$file" ]; then
      set -- "$@" "$file"
    fi
  done
fi

# Prints "<line number>:<text>" for each line of $1, YAML comments removed:
# a comment may name a forbidden command to explain why it is absent.
code_lines() {
  sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#.*$//' "$1" | grep -n -v '^[[:space:]]*$' || true
}

# Reports every code line of $1 that matches the extended regex $2, under
# the rule name $3. Lines that also match $4, when given, are allowed.
forbid() {
  local file="$1" regex="$2" rule="$3" allowed="${4:-}" entry number text
  while IFS= read -r entry; do
    number="${entry%%:*}"
    text="${entry#*:}"
    if [ -n "$allowed" ] && printf '%s\n' "$text" | grep -q -E -e "$allowed"; then
      continue
    fi
    report "$file" "$number" "$rule: ${text#"${text%%[![:space:]]*}"}"
  done < <(code_lines "$file" | grep -E -e "^[0-9]+:.*($regex)" || true)
}

check_pins() {
  local file="$1" entry number text ref
  while IFS= read -r entry; do
    number="${entry%%:*}"
    text="${entry#*:}"
    ref="$(printf '%s\n' "$text" | sed -e 's/^[[:space:]-]*uses:[[:space:]]*//' -e 's/[[:space:]]*$//' -e "s/^[\"']//" -e "s/[\"']\$//")"
    case "$ref" in
      ./*) continue ;;
    esac
    if printf '%s\n' "$ref" | grep -q -E -e '^docker://[^@[:space:]]+@sha256:[0-9a-f]{64}$'; then
      continue
    fi
    if printf '%s\n' "$ref" | grep -q -E -e '^[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}$'; then
      continue
    fi
    report "$file" "$number" "action not pinned by a full commit SHA: $ref"
  done < <(code_lines "$file" | grep -E -e '^[0-9]+:[[:space:]-]*uses:' || true)
}

word_start='(^|[^[:alnum:]_-])'
word_end='([^[:alnum:]_-]|$)'
separator='[^[:alnum:]_-]'

for file in "$@"; do
  if [ ! -f "$file" ]; then
    report "$file" 0 "workflow not found"
    continue
  fi
  # Principle X: no plan, apply or destroy, by OpenTofu or Terraform, nor by
  # a task of the gcp layer (decision of Lucas, 2026-11-20). One separator
  # after the tool name is enough: ERE has no lookahead, so the separator
  # that ends the tool name cannot also start the subcommand.
  forbid "$file" "${word_start}(tofu|terraform)${separator}(.*${separator})?(plan|apply|destroy)${word_end}" \
    "OpenTofu plan, apply or destroy"
  forbid "$file" "${word_start}gcp:(plan|apply|destroy)${word_end}" "task gcp:plan, gcp:apply or gcp:destroy"
  # No cloud credential: no Google authentication.
  forbid "$file" 'google-github-actions/auth|credentials_json|workload_identity_provider|GOOGLE_APPLICATION_CREDENTIALS|GOOGLE_GHA_CREDS_PATH|CLOUDSDK_AUTH' \
    "Google Cloud credential"
  forbid "$file" "${word_start}gcloud[[:space:]]+auth${word_end}" "Google Cloud credential (gcloud auth)"
  # No published plan.
  forbid "$file" "tfplan|${word_start}(tofu|terraform)[[:space:]]+show${word_end}|[[:space:]]-out[=[:space:]]" \
    "OpenTofu plan file or plan output"
  case "$file" in
    */.github/workflows/*)
      # In a workflow, no secret but the workflow token, and no OIDC token
      # for an identity federation.
      forbid "$file" 'secrets\.' "secret other than GITHUB_TOKEN" 'secrets\.GITHUB_TOKEN([^[:alnum:]_]|$)'
      forbid "$file" 'id-token:[[:space:]]*write' "OIDC token requested (id-token: write)"
      check_pins "$file"
      ;;
  esac
done

# Each failing case of the gcp layer, in gcp/tests/static/s17-cases/, is run
# through this script alone: it must fail, and its output must hold the text
# of the case's "# expect:" line. Without that folder (a project rendered for
# the local target alone), there is nothing to run.
check_cases() {
  local case_file expect out found=0
  for case_file in "$root"/gcp/tests/static/s17-cases/*.txt; do
    [ -f "$case_file" ] || continue
    found=$((found + 1))
    expect="$(awk -v key='# expect: ' 'NR > 10 { exit } index($0, key) == 1 { print substr($0, length(key) + 1); exit }' "$case_file")"
    if [ -z "$expect" ]; then
      report "$case_file" 0 "no '# expect:' line"
    elif out="$(bash "${BASH_SOURCE[0]}" "$case_file" 2>&1)"; then
      report "$case_file" 0 "accepted, yet it is a failing case: $expect"
    elif ! printf '%s\n' "$out" | grep -F -q -e "$expect"; then
      report "$case_file" 0 "refused, but no message holds: $expect"
    fi
  done
  if [ "$found" -eq 0 ]; then
    report "$root/gcp/tests/static/s17-cases" 0 "holds no failing case"
  fi
}

if [ "$default_run" -eq 1 ] && [ -d "$root/gcp/tests/static/s17-cases" ]; then
  check_cases
fi

if [ "$problems" -gt 0 ]; then
  exit 1
fi
