#!/usr/bin/env bash
# Applies the GitHub repository settings kept as code.
# Usage: scripts/github/apply-settings.sh [owner/repo]
# Needs: gh, authenticated with admin rights on the repository.
set -euo pipefail

repo="${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ruleset_file="$root/.github/rulesets/main.json"

echo "Repository: $repo"

# Squash merge only: the PR title becomes the commit on main, and commitlint
# checks that title in CI.
gh api --method PATCH "repos/$repo" \
  -F allow_squash_merge=true \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true \
  -f squash_merge_commit_title=PR_TITLE \
  -f squash_merge_commit_message=COMMIT_MESSAGES >/dev/null
echo "Merge settings applied."

# release-please opens its release PR with the workflow token, which needs
# this permission. The default token stays read-only.
gh api --method PUT "repos/$repo/actions/permissions/workflow" \
  -f default_workflow_permissions=read \
  -F can_approve_pull_request_reviews=true >/dev/null
echo "Workflow permissions applied."

# Rulesets are enforced on public repositories, or on private ones with a
# paid plan. On a private repository with GitHub Free the API answers 403.
if ! rulesets="$(gh api "repos/$repo/rulesets" 2>/dev/null)"; then
  echo "Rulesets unavailable here (private repository on GitHub Free). Skipped."
  exit 0
fi

ruleset_id="$(jq -r '.[] | select(.name == "main") | .id' <<<"$rulesets")"
if [[ -n "$ruleset_id" ]]; then
  gh api --method PUT "repos/$repo/rulesets/$ruleset_id" --input "$ruleset_file" >/dev/null
  echo "Ruleset main updated."
else
  gh api --method POST "repos/$repo/rulesets" --input "$ruleset_file" >/dev/null
  echo "Ruleset main created."
fi
