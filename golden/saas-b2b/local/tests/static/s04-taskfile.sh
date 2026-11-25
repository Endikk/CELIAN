#!/usr/bin/env bash
# control: S04
# carries: FR-004, FR-007; ADR-007, condition 1; ADR-011, condition 11; research RS-09
#
# Inventory part of S04 (T043). The head of Taskfile.yml lists every
# command of the tasks and of the scripts that creates, changes or removes
# a container, a network, a volume or a cluster, so that [SECU] reads them
# in one place (ADR-011, condition 11): a rule of permission reads the text
# of a command, not what a task runs. Each such command found in
# Taskfile.yml, local/tasks/*.yml and local/scripts/ has its line
#   #   <file>: <command>
# in the inventory, and each line of the inventory names a command that is
# still there.
#
# Secret part of S04 (T064; ADR-007, condition 1), on the same files:
# - no heredoc nor here-string, which bash 3.2 writes to a temporary file;
# - no kubectl apply of a Secret, nor from the standard input, which would
#   copy the value into the annotation last-applied-configuration; no
#   kubectl create secret, --from-literal, --from-env-file nor --save-config,
#   which put a value in an argument or an annotation; kubectl create -f -
#   in local/scripts/secrets.sh alone;
# - in local/scripts/secrets.sh, no trace (set -x, xtrace, bash -x), and the
#   output of /dev/urandom never lands in a variable;
# - no Task variable named after a password, a secret or a token, and no
#   dynamic variable (sh:) that reads one;
# - every task that runs local/scripts/secrets.sh is silent: Task prints a
#   command before it runs it; and one task at least runs it.
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
changing='(^|[^A-Za-z0-9_./-])(docker (container )?(run|create|rm|start|stop|kill|restart|rename|update|prune)|docker (volume|network) (create|rm|prune|connect|disconnect)|docker system prune|kind (create|delete) clusters?)( |$)'

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
  'kind delete clusters --all' \
  '# docker volume rm in a comment' \
  'docker volume inspect --format x "$VOLUME"' \
  'echo "run task down first"' >"$samples/sample.sh"
expected="$(printf '%s\n' \
  "$samples/sample.sh: docker run" \
  "$samples/sample.sh: docker container rm" \
  "$samples/sample.sh: docker volume create" \
  "$samples/sample.sh: kind delete cluster" \
  "$samples/sample.sh: kind delete clusters")"
got="$(found_commands "$samples/sample.sh")"
if [ "$got" != "$expected" ]; then
  echo "the detection of the changing commands found, on its samples:" >&2
  printf '%s\n' "$got" >&2
  exit 1
fi

secrets_script="local/scripts/secrets.sh"
# What would keep the output of /dev/urandom: a command substitution, old
# or new, or read.
urandom_capture='\$\(|`|read '

# secret_findings FILE: one line per command of FILE that breaks a rule of
# the secret part. The patterns spell the words with a class, so that this
# file does not match itself when a script reads it.
secret_findings() {
  local file="$1" number text
  while IFS=$'\t' read -r number text; do
    case "$text" in
      *'<''<'*) printf '%s:%s: heredoc or here-string, written to a temporary file by bash 3.2: %s\n' "$file" "$number" "$text" ;;
    esac
    if [[ $text =~ (kubectl|kube)\ .*appl[y]\ .*-f\ -( |$) ]] || [[ $text =~ appl[y].*[Ss]ecre[t] ]]; then
      printf '%s:%s: kubectl apply of a Secret or from the standard input, which copies the value into an annotation: %s\n' "$file" "$number" "$text"
    fi
    if [[ $text =~ create\ secre[t]|--from-litera[l]|--from-env-fil[e]|--save-confi[g] ]]; then
      printf '%s:%s: a value in an argument or in an annotation: %s\n' "$file" "$number" "$text"
    fi
    if [[ $text =~ (kubectl|kube)\ .*creat[e]\ .*-f\ -( |$) ]] && [ "${file##*/}" != "${secrets_script##*/}" ]; then
      printf '%s:%s: kubectl create from the standard input outside %s: %s\n' "$file" "$number" "$secrets_script" "$text"
    fi
    if [ "${file##*/}" = "${secrets_script##*/}" ]; then
      if [[ $text =~ set\ -[a-zA-Z]*x|xtrac[e]|bash\ -[a-zA-Z]*x ]]; then
        printf '%s:%s: a trace, which prints the commands and their values: %s\n' "$file" "$number" "$text"
      fi
      if [[ $text =~ /dev/urando[m] ]] && [[ $text =~ $urandom_capture ]]; then
        printf '%s:%s: the output of /dev/urandom in a variable: %s\n' "$file" "$number" "$text"
      fi
    fi
    case "$file" in
      *.yml)
        if [[ $text =~ (PASSWOR[D]|SECRE[T]|TOKE[N])[A-Z0-9_]*: ]] || [[ $text =~ sh:.*(urando[m]|secre[t]|passwor[d]) ]]; then
          printf '%s:%s: a Task variable that holds a secret: %s\n' "$file" "$number" "$text"
        fi
        ;;
    esac
  done < <(logical_lines "$file")
}

# secret_tasks FILE: "<file>:<task> <silent>" for each task of the Taskfile
# FILE that runs local/scripts/secrets.sh, <silent> 1 when it sets
# silent: true, 0 otherwise. Comment lines are left out.
secret_tasks() {
  awk -v script="$secrets_script" '
    function flush() {
      if (task != "" && runs) printf "%s:%s %d\n", FILENAME, task, silent
    }
    /^[[:space:]]*#/ { next }
    /^tasks:/ { in_tasks = 1; next }
    /^[^[:space:]]/ { flush(); in_tasks = 0; task = ""; next }
    in_tasks && /^  [A-Za-z0-9_:.-]+:[[:space:]]*$/ {
      flush()
      task = $1
      sub(/:$/, "", task)
      silent = 0
      runs = 0
      next
    }
    in_tasks && /^    silent:[[:space:]]*true[[:space:]]*$/ { silent = 1 }
    in_tasks && index($0, script) > 0 { runs = 1 }
    END { flush() }
  ' "$1"
}

printf '%s\n' \
  'printf "x" | kubectl create -f - <<EOF' \
  'kube apply -f - </dev/null' \
  'kubectl apply -f local/data/db-secret.yaml' \
  'kubectl create secret generic db-auth --from-literal=password=x' \
  'kube create -f - --save-config' \
  'kube create -f -' >"$samples/bad-other.sh"
printf '%s\n' \
  'set -x' \
  'password="$(head -c 40 /dev/urandom)"' \
  'read -r value </dev/urandom' >"$samples/secrets.sh"
printf '%s\n' \
  'version: 3' \
  'vars:' \
  '  DB_PASSWORD: x' \
  '  VALUE:' \
  '    sh: head -c 40 /dev/urandom' \
  'tasks:' \
  '  loud:' \
  '    cmds:' \
  '      - bash local/scripts/secrets.sh up' \
  '  quiet:' \
  '    silent: true' \
  '    cmds:' \
  '      - bash local/scripts/secrets.sh up' \
  '  other:' \
  '    cmds:' \
  '      - echo local/scripts/mirror.sh' >"$samples/bad.yml"
printf '%s\n' \
  '# kubectl apply -f - in a comment, and <<EOF' \
  'kube apply --server-side -f "$NAMESPACE_FILE" >/dev/null' \
  'head -c "$RANDOM_BYTES" /dev/urandom | LC_ALL=C tr -dc A-Za-z0-9 | cut -c 1-40' \
  '} | kube create -f - >/dev/null ||' \
  'kube --namespace "$APP_NAMESPACE" get secret "$1" --ignore-not-found --output name' >"$samples/good-secrets.sh"
mkdir "$samples/good"
cp "$samples/good-secrets.sh" "$samples/good/secrets.sh"
bad_count="$({ secret_findings "$samples/bad-other.sh"; secret_findings "$samples/secrets.sh"; secret_findings "$samples/bad.yml"; } | wc -l | tr -d ' ')"
if [ "$bad_count" != 13 ]; then
  echo "the rules of the secret part caught $bad_count of the 13 findings of their bad samples:" >&2
  { secret_findings "$samples/bad-other.sh"; secret_findings "$samples/secrets.sh"; secret_findings "$samples/bad.yml"; } >&2
  exit 1
fi
good_found="$(secret_findings "$samples/good/secrets.sh")"
if [ -n "$good_found" ]; then
  echo "the rules of the secret part refused good samples:" >&2
  printf '%s\n' "$good_found" >&2
  exit 1
fi
expected="$(printf '%s\n' "$samples/bad.yml:loud 0" "$samples/bad.yml:quiet 1")"
got="$(secret_tasks "$samples/bad.yml")"
if [ "$got" != "$expected" ]; then
  echo "the detection of the tasks that run $secrets_script found, on its sample:" >&2
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

# The secret part, on the real files.
secret_problems="$(command_files | while IFS= read -r file; do secret_findings "$file"; done)"
if [ -n "$secret_problems" ]; then
  echo "Commands that could expose a secret (ADR-007, condition 1):" >&2
  printf '  %s\n' "$secret_problems" >&2
  status=1
fi
runs="$(for file in Taskfile.yml local/tasks/*.yml; do [ -f "$file" ] && secret_tasks "$file"; done)"
if [ -z "$runs" ]; then
  echo "No task runs $secrets_script: the Secrets are not created by task up yet (spec 001, T068)." >&2
  status=1
fi
loud="$(printf '%s\n' "$runs" | awk '$2 == 0 { print $1 }')"
if [ -n "$loud" ]; then
  echo "Tasks that run $secrets_script without silent: true; Task would print their commands:" >&2
  printf '  %s\n' "$loud" >&2
  status=1
fi
if [ ! -f "$secrets_script" ]; then
  echo "$secrets_script is missing: it creates the Secrets of task up (spec 001, T068)." >&2
  status=1
fi
exit "$status"
