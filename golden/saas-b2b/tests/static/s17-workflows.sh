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
# such workflow. T105 adds the Taskfiles of gcp/. Arguments, if given,
# replace the default list.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

problems=0

report() {
  problems=$((problems + 1))
  printf '%s:%s: %s\n' "$1" "$2" "$3"
}

if [ "$#" -eq 0 ]; then
  for file in "$root"/.github/workflows/*.yml "$root"/.github/workflows/*.yaml; do
    if [ -f "$file" ]; then
      set -- "$@" "$file"
    fi
  done
  if [ "$#" -eq 0 ]; then
    report "$root/.github/workflows" 0 "no workflow found: the generated project has no CI (FR-013)"
  fi
  celian_root="$(cd "$root/../.." && pwd)"
  if [ "$celian_root/golden/saas-b2b" = "$root" ] && [ -d "$celian_root/.github/workflows" ]; then
    set -- "$@" "$celian_root/.github/workflows/golden-saas-b2b.yml"
  fi
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
  # No cloud credential: no secret but the workflow token, no OIDC token for
  # an identity federation, no Google authentication.
  forbid "$file" 'secrets\.' "secret other than GITHUB_TOKEN" 'secrets\.GITHUB_TOKEN([^[:alnum:]_]|$)'
  forbid "$file" 'id-token:[[:space:]]*write' "OIDC token requested (id-token: write)"
  forbid "$file" 'google-github-actions/auth|credentials_json|workload_identity_provider|GOOGLE_APPLICATION_CREDENTIALS|GOOGLE_GHA_CREDS_PATH|CLOUDSDK_AUTH' \
    "Google Cloud credential"
  forbid "$file" "${word_start}gcloud[[:space:]]+auth${word_end}" "Google Cloud credential (gcloud auth)"
  # No published plan.
  forbid "$file" "tfplan|${word_start}(tofu|terraform)[[:space:]]+show${word_end}|[[:space:]]-out[=[:space:]]" \
    "OpenTofu plan file or plan output"
  check_pins "$file"
done

if [ "$problems" -gt 0 ]; then
  exit 1
fi
