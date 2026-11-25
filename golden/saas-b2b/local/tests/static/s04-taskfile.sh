#!/usr/bin/env bash
# control: S04
# carries: FR-007; ADR-011, condition 11; research RS-09
#
# Inventory part of S04 (T043). The head of Taskfile.yml lists every
# command of the tasks and of the scripts that creates, changes or removes
# a container, a network, a volume or a cluster, so that [SECU] reads them
# in one place (ADR-011, condition 11): a rule of permission reads the text
# of a command, not what a task runs. Each such command found in
# Taskfile.yml, local/tasks/*.yml and local/scripts/ has its line
#   #   <file>: <command>
# in the inventory, and each line of the inventory names a command that is
# still there. Step 8 adds the rules on the tasks that handle a secret
# (T064).
#
# The detection is first checked against samples.
# The samples and the flags are shell text, read and never expanded here.
# shellcheck disable=SC2016,SC1003
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
CDPATH='' cd -- "$root"
# shellcheck disable=SC1091 # lib/command-lines.sh is checked on its own
. local/tests/static/lib/command-lines.sh

# The commands that change the engine or a cluster, as written in the files.
changing='(^|[^A-Za-z0-9_./-])(docker (container )?(run|create|rm|start|stop|kill|restart|rename|update|prune)|docker (volume|network) (create|rm|prune|connect|disconnect)|docker system prune|kind (create|delete) cluster)( |$)'

# found_commands FILE: "<file>: <command>" for each changing command of FILE.
found_commands() {
  local file="$1" text rest
  while IFS=$'\t' read -r _ text; do
    rest="$text"
    while [[ $rest =~ $changing ]]; do
      printf '%s: %s\n' "$file" "${BASH_REMATCH[2]}"
      rest="${rest#*"${BASH_REMATCH[2]}"}"
    done
  done < <(logical_lines "$file")
}

# The inventory: the comment lines "#   <file>: <command>" at the head of
# Taskfile.yml, before its first line that is not a comment.
inventory() {
  awk '
    !/^#/ { exit }
    /^#   [^ ]+: / { sub(/^#   /, ""); print }
  ' Taskfile.yml
}

samples="$(mktemp -d)"
trap 'rm -rf "${samples:?}"' EXIT
printf '%s\n' \
  'docker run --detach --name x image' \
  'docker container rm --force "$NAME"' \
  'docker volume create --label a=b "$VOLUME"' \
  'kind delete cluster --name "$CLUSTER_NAME" \' \
  '  --kubeconfig "$KUBECONFIG_FILE"' \
  '# docker volume rm in a comment' \
  'docker volume inspect --format x "$VOLUME"' \
  'echo "run task down first"' >"$samples/sample.sh"
expected="$(printf '%s\n' \
  "$samples/sample.sh: docker run" \
  "$samples/sample.sh: docker container rm" \
  "$samples/sample.sh: docker volume create" \
  "$samples/sample.sh: kind delete cluster")"
got="$(found_commands "$samples/sample.sh")"
if [ "$got" != "$expected" ]; then
  echo "the detection of the changing commands found, on its samples:" >&2
  printf '%s\n' "$got" >&2
  exit 1
fi

found="$(command_files | while IFS= read -r file; do found_commands "$file"; done | LC_ALL=C sort -u)"
listed="$(inventory | LC_ALL=C sort -u)"

missing="$(LC_ALL=C comm -23 <(printf '%s\n' "$found") <(printf '%s\n' "$listed") | grep . || true)"
stale="$(LC_ALL=C comm -13 <(printf '%s\n' "$found") <(printf '%s\n' "$listed") | grep . || true)"
status=0
if [ -n "$missing" ]; then
  echo "Commands that change a container, a network, a volume or a cluster, absent from the inventory at the head of Taskfile.yml:" >&2
  printf '  %s\n' "$missing" >&2
  status=1
fi
if [ -n "$stale" ]; then
  echo "Lines of the inventory at the head of Taskfile.yml that name no command any more:" >&2
  printf '  %s\n' "$stale" >&2
  status=1
fi
if [ -z "$found" ]; then
  echo "No command of the tasks creates the cluster or the mirror: task up is not wired yet (spec 001, T050)." >&2
  status=1
fi
exit "$status"
