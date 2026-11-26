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
# gcp layer and of its budget root (T110), where the OpenTofu commands live.
# They get the rules of principle X (no plan, apply or destroy, no Google
# credential, no published plan); the rules on secrets, OIDC tokens and pins
# are for workflows only.
#
# The gcp layer gets a stricter rule, an allowlist, until GATE 2: in its
# Taskfile and scripts, OpenTofu runs only fmt, init (with -backend=false),
# validate, version and providers; gcloud does not appear, and kubectl only as
# `kubectl kustomize`, a render that calls no cluster (step 14). A list of
# what is refused would miss import, state, console or taint. The failing
# cases are in gcp/tests/static/s17-cases/, run through this script alone.
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
    "$root"/gcp/tests/static/*.sh "$root"/gcp/scripts/*.sh \
    "$root"/gcp/budget/*.sh "$root"/gcp/budget/*.yml; do
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

# Allowlist of the gcp layer, until GATE 2 (principle X). Reads the code
# lines of $1 and, for each use of tofu or terraform, takes the first word
# after its options as the subcommand. Prints "<line>|<rule>|<text>" for a
# subcommand outside fmt, init, validate, version and providers, and for an
# init without -backend=false on the same line. A use with no subcommand
# (command -v tofu, a path) passes. A word in a message counts too: write
# "OpenTofu" there, which is not matched.
gcp_tofu_findings() {
  code_lines "$1" | awk '
    {
      split_at = index($0, ":")
      number = substr($0, 1, split_at - 1)
      text = substr($0, split_at + 1)
      rest = text
      while (match(rest, /(^|[^A-Za-z0-9_.\/-])(tofu|terraform)([^A-Za-z0-9_.\/-]|$)/)) {
        seg = substr(rest, RSTART, RLENGTH)
        skip = (substr(seg, 1, 1) == "t") ? 0 : 1
        tool_len = (substr(seg, skip + 1, 9) == "terraform") ? 9 : 4
        rest = substr(rest, RSTART + skip + tool_len)
        tail = rest
        sub_cmd = ""
        while (tail != "") {
          sub(/^[ \t]+/, "", tail)
          if (tail == "") { break }
          word = tail
          sub(/[ \t].*$/, "", word)
          if (word ~ /^-/) { tail = substr(tail, length(word) + 1); continue }
          if (match(word, /^[a-z][a-z-]*/)) { sub_cmd = substr(word, 1, RLENGTH) }
          break
        }
        if (sub_cmd == "") { continue }
        if (sub_cmd !~ /^(fmt|init|validate|version|providers)$/) {
          print number "|OpenTofu command outside the allowlist of the gcp layer (fmt, init, validate, version, providers)|" text
        } else if (sub_cmd == "init" && text !~ /(^|[ \t])-backend=false([ \t]|$)/) {
          print number "|OpenTofu init without -backend=false|" text
        }
      }
    }
  ' || true
}

# Allowlist of kubectl in the gcp layer, until GATE 2 (principle X; step 14).
# The checks of the Kubernetes layer render it with `kubectl kustomize`, which
# reads files and calls no cluster: no kubeconfig, no context, no network.
# Every other use of kubectl is refused, because a call to a GKE context
# would create billed resources outside the state of OpenTofu, a load
# balancer for a Gateway for instance (ADR-005, CLAUDE.md, "Garde-fous").
# Takes the first word after the options as the subcommand, as the OpenTofu
# allowlist does, and prints "<line>|<rule>|<text>" for each use whose
# subcommand is not kustomize. A use with no subcommand ("for tool in
# kubectl; do", "command -v kubectl") passes. An option that takes a value,
# --context gke_x, leaves the value as the subcommand, which is refused: the
# conservative reading.
gcp_kubectl_findings() {
  code_lines "$1" | awk '
    {
      split_at = index($0, ":")
      number = substr($0, 1, split_at - 1)
      text = substr($0, split_at + 1)
      rest = text
      while (match(rest, /(^|[^A-Za-z0-9_.\/-])kubectl([^A-Za-z0-9_.\/-]|$)/)) {
        seg = substr(rest, RSTART, RLENGTH)
        skip = (substr(seg, 1, 1) == "k") ? 0 : 1
        rest = substr(rest, RSTART + skip + 7)
        tail = rest
        sub_cmd = ""
        while (tail != "") {
          sub(/^[ \t]+/, "", tail)
          if (tail == "") { break }
          word = tail
          sub(/[ \t].*$/, "", word)
          if (word ~ /^-/) { tail = substr(tail, length(word) + 1); continue }
          if (match(word, /^[A-Za-z][A-Za-z-]*/)) { sub_cmd = substr(word, 1, RLENGTH) }
          break
        }
        if (sub_cmd == "") { continue }
        if (sub_cmd != "kustomize") {
          print number "|kubectl command outside the allowlist of the gcp layer (kustomize, a render with no cluster)|" text
        }
      }
    }
  ' || true
}

# The rules of the gcp layer, for its Taskfile and its scripts.
check_gcp_layer() {
  local file="$1" number rule text
  forbid "$file" "${word_start}gcloud${word_end}" \
    "gcloud in the gcp layer, before GATE 2"
  while IFS='|' read -r number rule text; do
    [ -n "$number" ] || continue
    report "$file" "$number" "$rule: ${text#"${text%%[![:space:]]*}"}"
  done < <(gcp_kubectl_findings "$file"; gcp_tofu_findings "$file")
}

# The write permissions of release-please.yml ($2 is their pattern): exactly
# three lines, so that a job added to this file cannot ask for more.
check_release_please_writes() {
  local file="$1" pattern="$2" count
  count="$(code_lines "$file" | grep -c -E -e "^[0-9]+:${pattern#^}" || true)"
  if [ "$count" != "3" ]; then
    report "$file" 0 "release-please.yml must hold the three write permissions once (contents, issues, pull-requests), found $count"
  fi
}

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
    */gcp/tasks/* | */gcp/tests/static/* | */gcp/scripts/* | */gcp/budget/*)
      check_gcp_layer "$file"
      ;;
  esac
  case "$file" in
    */.github/workflows/* | */tests/static/s17-workflow-cases/*.yml)
      # In a workflow, no secret but the workflow token, and no OIDC token
      # for an identity federation.
      forbid "$file" 'secrets\.' "secret other than GITHUB_TOKEN" 'secrets\.GITHUB_TOKEN([^[:alnum:]_]|$)'
      forbid "$file" 'id-token:[[:space:]]*write' "OIDC token requested (id-token: write)"
      # The workflows run on pull requests with the code of the pull request,
      # under a read-only token. The two triggers that run with the secrets
      # and a writable token of the base repository are refused, as is any
      # permission set to write, at the top or in any job, even one added later.
      forbid "$file" "${word_start}(pull_request_target|workflow_run)${word_end}" \
        "trigger pull_request_target or workflow_run (runs with the token and secrets of the base repository)"
      # One workflow needs to write: release-please.yml opens the release PR.
      # It may set exactly contents, issues and pull-requests to write, once.
      write_allowed=''
      case "$file" in
        */.github/workflows/release-please.yml)
          write_allowed='^[[:space:]]+(contents|issues|pull-requests):[[:space:]]*write[[:space:]]*$'
          check_release_please_writes "$file" "$write_allowed"
          ;;
      esac
      forbid "$file" "[a-z-]+[[:space:]]*:[[:space:]]*[\"']?write(-all)?[\"']?[[:space:]]*(,|}|\$)" \
        "permission set to write or write-all" "$write_allowed"
      # A download that runs as it arrives: nothing checks what is executed.
      # The tools come from tests/tools/install.sh, checked against SHA256SUMS.
      forbid "$file" "(^|[^|])\\|[[:space:]]*((sudo|env|exec)[[:space:]]+)?([^|[:space:]]*/)?(sh|bash|zsh|dash|ksh|python[0-9.]*|perl|ruby|node)${word_end}" \
        "output piped into a shell or an interpreter (curl | sh)"
      forbid "$file" "${word_start}(sh|bash|zsh|dash|ksh|source|eval)${word_end}.*(<\\(|\\\$\\()[[:space:]]*(curl|wget)${word_end}" \
        "download run by a shell as it arrives (bash <(curl ...))"
      check_pins "$file"
      ;;
  esac
done

# Each failing case, in gcp/tests/static/s17-cases/ (the gcp layer) and in
# tests/static/s17-workflow-cases/ (the workflows), is run
# through this script alone: it must fail, and its output must hold the text
# of the case's "# expect:" line. Without that folder (a project rendered for
# the local target alone), there is nothing to run.
check_cases() {
  local dir="$1" extension="$2"
  local case_file expect out found=0
  for case_file in "$dir"/*."$extension"; do
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
    report "$dir" 0 "holds no failing case"
  fi
}

if [ "$default_run" -eq 1 ]; then
  if [ -d "$root/gcp/tests/static/s17-cases" ]; then
    check_cases "$root/gcp/tests/static/s17-cases" txt
  fi
  check_cases "$root/tests/static/s17-workflow-cases" yml
fi

if [ "$problems" -gt 0 ]; then
  exit 1
fi
