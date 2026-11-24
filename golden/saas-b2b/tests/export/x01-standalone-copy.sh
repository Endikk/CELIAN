#!/usr/bin/env bash
# control: X01
# carries: FR-013; constitution, principle IX
#
# The golden repo works as a project of its own. Copies it into a new Git
# repository, outside CELIAN, and checks there that its hooks pass on every
# file, that its commitlint refuses a message outside Conventional Commits
# and accepts one that follows them, that actionlint passes on its
# workflows, that its actions are pinned by SHA (S17 on the copy), and that
# gitleaks passes on its history. GitHub runs no workflow from a subfolder
# (research RS-17): this copy is where they get exercised.
#
# Needs git, pre-commit and docker, and the network: pre-commit installs the
# hook environments, docker pulls the gitleaks image. Runs in CI, in the job
# export of .github/workflows/golden-saas-b2b.yml.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
  printf 'X01: %s\n' "$1" >&2
  exit 1
}

step() {
  printf '\n== X01: %s\n' "$1"
}

for tool in git pre-commit docker; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    fail "$tool is not installed. X01 runs in CI, job export of golden-saas-b2b.yml."
  fi
done

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir" 2>/dev/null || true' EXIT
copy="$workdir/project"
mkdir "$copy"

step "copy the golden repo into a new Git repository"
# The files Git tracks or would track: the copy holds what a commit holds,
# without ignored files such as .task/.
git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || fail "$root is not in a Git repository."
copied=0
while IFS= read -r -d '' file; do
  # A file deleted from the work tree but still in the index.
  [ -f "$root/$file" ] || continue
  mkdir -p "$copy/$(dirname "$file")"
  cp -p "$root/$file" "$copy/$file"
  copied=$((copied + 1))
done < <(git -C "$root" ls-files -z --cached --others --exclude-standard -- .)
[ "$copied" -gt 0 ] || fail "no file to copy from $root."
printf '%s files copied.\n' "$copied"

cd "$copy"
git init -q
git config user.name "X01"
git config user.email "x01@saas-b2b.invalid"
git config commit.gpgsign false

[ -f .pre-commit-config.yaml ] || fail "the copy has no .pre-commit-config.yaml (FR-013)."

step "install the hooks of the copy"
pre-commit install
[ -x .git/hooks/pre-commit ] || fail "pre-commit install wrote no pre-commit hook."
[ -x .git/hooks/commit-msg ] || fail "pre-commit install wrote no commit-msg hook: default_install_hook_types must list commit-msg (FR-013)."

step "run every hook on every file"
git add -A
pre-commit run --all-files --show-diff-on-failure || fail "the hooks of the copy fail on its own files (FR-013)."

step "commitlint refuses a message outside Conventional Commits, and accepts one that follows them"
bad_message="Update stuff"
good_message="feat: add the first note"
printf '%s\n' "$bad_message" >"$workdir/bad-message"
printf '%s\n' "$good_message" >"$workdir/good-message"
if pre-commit run commitlint --hook-stage commit-msg --commit-msg-filename "$workdir/bad-message"; then
  fail "commitlint accepted '$bad_message', which has no type (FR-013)."
fi
pre-commit run commitlint --hook-stage commit-msg --commit-msg-filename "$workdir/good-message" ||
  fail "commitlint refused '$good_message' (FR-013)."

step "the installed hooks refuse the commit of a bad message, then accept a good one"
if git commit -q -m "$bad_message"; then
  fail "git commit accepted '$bad_message': the commit-msg hook does not run commitlint (FR-013)."
fi
if git rev-parse -q --verify HEAD >/dev/null; then
  fail "a commit exists after a refused message."
fi
git commit -q -m "$good_message" || fail "git commit refused '$good_message'; see the hook output above."

step "actionlint passes on the workflows of the copy"
set -- .github/workflows/*.yml
[ -f "$1" ] || fail "the copy has no workflow in .github/workflows/ (FR-013)."
pre-commit run actionlint --files "$@" || fail "actionlint fails on the workflows of the copy."

step "every action of the copy is pinned by a full commit SHA (S17 on the copy)"
bash tests/static/s17-workflows.sh || fail "S17 fails on the workflows of the copy."

step "gitleaks passes on the history of the copy"
image="$(sed -n -e 's/^[[:space:]]*GITLEAKS_IMAGE:[[:space:]]*//p' .github/workflows/secrets.yml | head -n 1)"
if ! printf '%s\n' "$image" | grep -q -E -e '^[^[:space:]@]+@sha256:[0-9a-f]{64}$'; then
  fail "GITLEAKS_IMAGE of .github/workflows/secrets.yml is not an image pinned by digest: '$image'."
fi
docker run --rm -v "$copy:/repo" "$image" git /repo --redact --verbose ||
  fail "gitleaks fails on the history of the copy (principle IX)."

printf '\nX01: the golden repo works as a project of its own.\n'
