#!/usr/bin/env bash
# control: S04
# carries: FR-004, FR-007; ADR-007, condition 1; ADR-011, condition 11; research RS-09, RS-10
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
# - no trace (set -x, set -o xtrace, bash -x) in local/scripts/secrets.sh,
#   in local/scripts/app.sh nor in local/tests/e2e/: a trace in E04 or E06
#   would print a password. In local/scripts/secrets.sh, the output of
#   /dev/urandom also never lands in a variable;
# - no Task variable named after a password, a secret or a token, and no
#   dynamic variable (sh:) that reads one;
# - every task that runs local/scripts/secrets.sh is silent: Task prints a
#   command before it runs it; and one task at least runs it.
#
# Key part of S04 (T072; research RS-10), on the same files: the key and the
# certificate of gateway-tls come from one openssl req that writes both to
# its standard output, and no file ever holds them. So:
# - openssl req without -keyout /dev/stdout (without it, req writes the key
#   to the default_keyfile of the configuration, privkey.pem in some); any
#   -keyout or -out to another path, on req, genpkey, genrsa, ecparam,
#   x509 -signkey and the other commands that make or convert a key;
# - a redirection, tee or mktemp on the output of those commands, and a
#   redirection to a file anywhere in local/scripts/secrets.sh;
# - the PEM in a variable or in an argument: a command substitution, read,
#   export, env or base64 on those commands; base64 in local/scripts/secrets.sh;
#   tls.key read into a variable (its length goes through wc -c);
# - kubectl create secret tls, which asks for --cert and --key as paths of
#   files, and --from-file, like create secret generic and --from-literal.
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
    if [[ $text =~ create\ secre[t]|--from-litera[l]|--from-fil[e]|--from-env-fil[e]|--save-confi[g] ]]; then
      printf '%s:%s: a value in an argument, in a file or in an annotation (create secret tls asks for files): %s\n' "$file" "$number" "$text"
    fi
    if [[ $text =~ (kubectl|kube)\ .*creat[e]\ .*-f\ -( |$) ]] && [ "${file##*/}" != "${secrets_script##*/}" ]; then
      printf '%s:%s: kubectl create from the standard input outside %s: %s\n' "$file" "$number" "$secrets_script" "$text"
    fi
    if [ "${file##*/}" = "${secrets_script##*/}" ]; then
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

# The commands of openssl that make or convert a key or a certificate (x509
# and ca too, for -signkey and -out), and, among them, those that handle the
# private key itself. The word openssl may follow any path, so "/" is not
# excluded before it (/opt/homebrew/bin/openssl), and a variable that holds
# the command ("$OPENSSL") is read as the word itself (see openssl_normalized).
openssl_call='(^|[^A-Za-z0-9_.-])openssl (req|genpkey|genrsa|gendsa|dsaparam|ecparam|pkcs12|pkcs8|pkey|rsa|ec|enc|cms|x509|ca)( |$)'
openssl_key='(^|[^A-Za-z0-9_.-])openssl (req|genpkey|genrsa|gendsa|dsaparam|ecparam|pkcs12|pkcs8|pkey|rsa|ec|enc|cms)( |$)'
openssl_req='(^|[^A-Za-z0-9_.-])openssl req( |$)'
openssl_word='(^|[^A-Za-z0-9_.-])openssl([^A-Za-z0-9_]|$)'
openssl_variable='"?\$\{?[A-Za-z0-9_]*[Oo][Pp][Ee][Nn][Ss][Ss][Ll][A-Za-z0-9_]*\}?"?'
openssl_out='-(key)?out +([^ ]+)'
req_keyout='-keyout /dev/stdout( |$)'
to_null='>/dev/null'
# What would keep a PEM in a variable or an argument, and the commands that
# write a copy of their input to a file.
pem_capture='\$\(|`|(^|[ ;|])(read|mapfile|readarray|export|env|base64)( |$)'
read_capture='\$\(|`|(^|[ ;|])read '
copy_writer='(^|[ ;|&(])(tee|mktemp|dd|cp|mv|install|sponge)( |$)'
base64_word='(^|[^A-Za-z0-9_])base64( |$)'
tls_key_field='tls\\?\.key'
wc_length='wc -c'
# What secrets.sh may run of openssl, and nothing else: openssl req (with
# -keyout /dev/stdout, checked on its own) and openssl x509 -noout -checkend.
allowed_req='openssl req '
allowed_checkend='openssl x509 -noout -checkend '

# openssl_normalized TEXT: TEXT with each variable that names openssl
# ("$OPENSSL", ${OPENSSL_BIN}) written as the word openssl, so that the rules
# below see the command whatever way it is spelled. Prints it.
openssl_normalized() {
  local text="$1"
  while [[ $text =~ $openssl_variable ]]; do
    text="${text/"${BASH_REMATCH[0]}"/openssl}"
  done
  printf '%s' "$text"
}

# tls_findings FILE: one line per rule that a command of FILE breaks, in the
# key part of S04 (research RS-10).
tls_findings() {
  local file="$1" number text norm rest stripped path
  local in_secrets=no
  [ "${file##*/}" = "${secrets_script##*/}" ] && in_secrets=yes
  while IFS=$'\t' read -r number text; do
    norm="$(openssl_normalized "$text")"
    if [[ $norm =~ $openssl_call ]]; then
      rest="$norm"
      while [[ $rest =~ $openssl_out ]]; do
        path="${BASH_REMATCH[2]%%[)\";|&]*}"
        if [ "$path" != /dev/stdout ]; then
          printf '%s:%s: openssl writes to the path %s, not to /dev/stdout: %s\n' "$file" "$number" "$path" "$text"
          break
        fi
        rest="${rest#*"${BASH_REMATCH[0]}"}"
      done
      if [[ $norm =~ $openssl_req ]] && ! [[ $norm =~ $req_keyout ]]; then
        printf '%s:%s: openssl req without -keyout /dev/stdout writes the key to the file of its configuration: %s\n' "$file" "$number" "$text"
      fi
      stripped="${norm//$to_null/}"
      case "$stripped" in
        *'>'*) printf '%s:%s: a redirection on the output of openssl: %s\n' "$file" "$number" "$text" ;;
      esac
      if [[ $norm =~ $copy_writer ]]; then
        printf '%s:%s: a command that copies the output of openssl to a file (tee, mktemp, dd, cp, mv, install, sponge): %s\n' "$file" "$number" "$text"
      fi
    fi
    if [[ $norm =~ $openssl_key ]] && [[ $norm =~ $pem_capture ]]; then
      printf '%s:%s: the PEM of openssl in a variable or an argument: %s\n' "$file" "$number" "$text"
    fi
    if [[ $text =~ $tls_key_field ]] && [[ $text =~ $read_capture ]] && ! [[ $text =~ $wc_length ]]; then
      printf '%s:%s: tls.key read into a variable; only its length may be read, through wc -c: %s\n' "$file" "$number" "$text"
    fi
    if [ "$in_secrets" = yes ]; then
      if [[ $text =~ $base64_word ]]; then
        printf '%s:%s: base64 in %s, which writes the PEM as it is in stringData: %s\n' "$file" "$number" "$secrets_script" "$text"
      fi
      if [[ $norm =~ $copy_writer ]] && ! [[ $norm =~ $openssl_call ]]; then
        printf '%s:%s: tee, mktemp, dd, cp, mv, install or sponge in %s: %s\n' "$file" "$number" "$secrets_script" "$text"
      fi
      stripped="${text//$to_null/}"
      stripped="${stripped//>&[0-9]/}"
      case "$stripped" in
        *'>'*) printf '%s:%s: a redirection to a file in %s: %s\n' "$file" "$number" "$secrets_script" "$text" ;;
      esac
      # The white list: with openssl req and openssl x509 -noout -checkend
      # taken out, no word openssl is left.
      rest="${norm//$allowed_req/}"
      rest="${rest//$allowed_checkend/}"
      if [[ $rest =~ $openssl_word ]]; then
        printf '%s:%s: %s runs only openssl req and openssl x509 -noout -checkend, nothing else of openssl: %s\n' "$file" "$number" "$secrets_script" "$text"
      fi
    fi
  done < <(logical_lines "$file")
}

# traced FILE: success when a trace in FILE could print a password: the
# script that creates the Secrets, the script that reads them, and every
# file of the end-to-end tests (spaces in the pattern kept out of the way).
traced() {
  case "/$1" in
    */secrets.sh | */local/scripts/app.sh | */local/tests/e2e/*) return 0 ;;
  esac
  return 1
}

# trace_files: the real files that traced accepts, one per line.
trace_files() {
  local file
  for file in "$secrets_script" local/scripts/app.sh local/tests/e2e/*.sh local/tests/e2e/lib/*.sh; do
    [ -f "$file" ] && printf '%s\n' "$file"
  done
}

# trace_findings FILE: one line per command of FILE that turns a trace on.
trace_findings() {
  local file="$1" number text
  traced "$file" || return 0
  while IFS=$'\t' read -r number text; do
    if [[ $text =~ set\ -[a-zA-Z]*x|set\ .*-o\ xtrac[e]|xtrac[e]|bash\ -[a-zA-Z]*x ]]; then
      printf '%s:%s: a trace, which prints the commands and their values: %s\n' "$file" "$number" "$text"
    fi
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
if [ "$bad_count" != 12 ]; then
  echo "the rules of the secret part caught $bad_count of the 12 findings of their bad samples:" >&2
  { secret_findings "$samples/bad-other.sh"; secret_findings "$samples/secrets.sh"; secret_findings "$samples/bad.yml"; } >&2
  exit 1
fi
# The trace: the three places where a password could be printed, and a file
# outside them that the rule leaves alone.
mkdir -p "$samples/local/scripts" "$samples/local/tests/e2e/lib"
printf '%s\n' 'set -x' 'bash -x other.sh' >"$samples/local/scripts/app.sh"
printf '%s\n' 'set -euxo pipefail' 'set -o xtrace' >"$samples/local/tests/e2e/e99-bad.sh"
printf '%s\n' 'echo ok' 'set -x' >"$samples/local/tests/e2e/lib/helper.sh"
printf '%s\n' 'set -x' >"$samples/other.sh"
printf '%s\n' '# set -x in a comment' 'set -euo pipefail' 'bash local/scripts/app.sh' >"$samples/local/tests/e2e/e98-good.sh"
trace_bad="$({ for f in "$samples/secrets.sh" "$samples/local/scripts/app.sh" "$samples/local/tests/e2e/e99-bad.sh" "$samples/local/tests/e2e/lib/helper.sh"; do trace_findings "$f"; done; } | wc -l | tr -d ' ')"
if [ "$trace_bad" != 6 ]; then
  echo "the rule of the trace caught $trace_bad of the 6 findings of its bad samples (secrets.sh, app.sh, e2e):" >&2
  exit 1
fi
trace_good="$({ trace_findings "$samples/other.sh"; trace_findings "$samples/local/tests/e2e/e98-good.sh"; trace_findings "$samples/good/secrets.sh"; } | wc -l | tr -d ' ')"
if [ "$trace_good" != 0 ]; then
  echo "the rule of the trace refused good samples or a file outside its scope" >&2
  exit 1
fi
good_found="$(secret_findings "$samples/good/secrets.sh")"
if [ -n "$good_found" ]; then
  echo "the rules of the secret part refused good samples:" >&2
  printf '%s\n' "$good_found" >&2
  exit 1
fi
# The key part (research RS-10): every refused form of the list of T072, one
# finding each unless the count says two; then the commands of RS-10 itself.
printf '%s\n' \
  'openssl req -x509 -newkey ec -nodes -keyout key.pem -out cert.pem' \
  'openssl req -x509 -newkey ec -nodes -out /dev/stdout' \
  'openssl req -x509 -nodes -keyout /dev/stdout -out /dev/stdout > cert.pem' \
  'openssl req -x509 -nodes -keyout /dev/stdout -out /dev/stdout | tee cert.pem' \
  'key="$(openssl req -x509 -nodes -keyout /dev/stdout -out /dev/stdout)"' \
  'openssl genpkey -algorithm EC -out key.pem' \
  'openssl genrsa -out key.pem 2048' \
  'openssl ecparam -genkey -name prime256v1 -out key.pem' \
  'openssl x509 -req -signkey key.pem -out cert.pem' \
  'kubectl create secret tls gateway-tls --cert=c --key=k' \
  'kubectl create secret generic gateway-tls --from-file=tls.key=key.pem' \
  'kube create configmap pem --from-file=a=b' \
  'crt="$(kube get secret gateway-tls --output jsonpath={.data.tls\.key})"' \
  'openssl req -x509 -nodes -keyout /dev/stdout -out /dev/stdout | base64' \
  '/opt/homebrew/bin/openssl req -x509 -newkey ec -nodes -keyout key.pem -out cert.pem' \
  'openssl pkcs8 -topk8 -nocrypt -out key.pem' \
  '"$OPENSSL" req -x509 -nodes -keyout k.pem -out c.pem' \
  'openssl req -x509 -nodes -keyout /dev/stdout -out /dev/stdout | dd of=k.pem' \
  'openssl req -x509 -nodes -keyout /dev/stdout -out /dev/stdout | cp /dev/stdin k.pem' \
  'openssl enc -aes-256-cbc -in a -out k.enc' \
  'openssl cms -sign -in a -out k.cms' >"$samples/bad-tls.sh"
mkdir "$samples/bad-tls"
printf '%s\n' \
  'base64 -d' \
  'cat | tee out.pem' \
  'head -c 8 /dev/urandom > seed' \
  'dd of=k.pem' \
  'cat | cp /dev/stdin k.pem' \
  'mv a k.pem' \
  'install -m 600 a k.pem' \
  'sponge k.pem' \
  'openssl pkcs8 -topk8 -nocrypt -out key.pem' \
  'openssl s_client -connect 127.0.0.1:18443' \
  '"$OPENSSL" x509 -in a -noout -text' >"$samples/bad-tls/secrets.sh"
printf '%s\n' \
  '# openssl req -keyout key.pem in a comment' \
  '{' \
  '  printf '"'"'apiVersion: v1\nkind: Secret\nstringData:\n'"'"' "$APP_NAMESPACE"' \
  '  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \' \
  '    -keyout /dev/stdout -out /dev/stdout -days 365 -subj /CN=localhost \' \
  '    -addext subjectAltName=DNS:localhost,IP:127.0.0.1 2>/dev/null |' \
  '    awk '"'"'/^-----BEGIN [A-Z ]*PRIVATE KEY-----$/ { print "  tls.key: |" }'"'"'' \
  '} | kube create -f - >/dev/null ||' \
  '  die "the Secret was not created."' \
  'length="$(kube get secret gateway-tls --output '"'"'jsonpath={.data.tls\.key}'"'"' | wc -c | tr -d '"'"' '"'"')"' \
  'kube get secret gateway-tls --output '"'"'jsonpath={.data.tls\.crt}'"'"' | openssl x509 -noout -checkend 2592000 >/dev/null' \
  'printf '"'"'secrets: %s\n'"'"' "$1" >&2' >>"$samples/good/secrets.sh"
tls_bad_other="$({ tls_findings "$samples/bad-tls.sh"; secret_findings "$samples/bad-tls.sh"; } | wc -l | tr -d ' ')"
tls_bad_secrets="$({ tls_findings "$samples/bad-tls/secrets.sh"; secret_findings "$samples/bad-tls/secrets.sh"; } | wc -l | tr -d ' ')"
if [ "$tls_bad_other" != 24 ] || [ "$tls_bad_secrets" != 12 ]; then
  echo "the key part caught $tls_bad_other of the 24 findings of its bad samples, and $tls_bad_secrets of the 12 of its bad secrets.sh:" >&2
  { tls_findings "$samples/bad-tls.sh"; secret_findings "$samples/bad-tls.sh"; tls_findings "$samples/bad-tls/secrets.sh"; secret_findings "$samples/bad-tls/secrets.sh"; } >&2
  exit 1
fi
tls_good_found="$(tls_findings "$samples/good/secrets.sh"; secret_findings "$samples/good/secrets.sh")"
if [ -n "$tls_good_found" ]; then
  echo "the key part refused the good samples, the commands of research RS-10:" >&2
  printf '%s\n' "$tls_good_found" >&2
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
secret_problems="$(command_files | while IFS= read -r file; do secret_findings "$file"; tls_findings "$file"; done)"
if [ -n "$secret_problems" ]; then
  echo "Commands that could expose a secret (ADR-007, condition 1):" >&2
  printf '  %s\n' "$secret_problems" >&2
  status=1
fi
trace_problems="$(trace_files | while IFS= read -r file; do trace_findings "$file"; done)"
if [ -n "$trace_problems" ]; then
  echo "Traces that could print a password (ADR-007, condition 1):" >&2
  printf '  %s\n' "$trace_problems" >&2
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
