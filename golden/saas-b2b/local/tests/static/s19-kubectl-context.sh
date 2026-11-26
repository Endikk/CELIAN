#!/usr/bin/env bash
# control: S19
# carries: FR-019; ADR-004, condition 9; research RS-21
#
# Every kubectl call of the tasks and of the scripts names the kubeconfig of
# the project and the context of the local cluster, so that no command ever
# reaches the cluster of the default kubeconfig of the user, a GKE context
# above all (FR-019). Two calls read no kubeconfig and are the exceptions:
# "kubectl version --client" of the preflight checks (research RS-08), and
# "kubectl kustomize", which renders files and builds no client, for the
# inventory of the images (research RS-24), on a line that runs no other
# kubectl.
# A port-forward listens on 127.0.0.1 only. The kind commands that write or
# remove a kubeconfig entry name the same file and the cluster, plural form
# included (kind delete clusters). No docker command carries a global option
# (--context, -H, --host): it would aim the command at another engine. Nothing sets
# KUBECONFIG. The two values come from local/scripts/lib/local-env.sh, which
# keeps the kubeconfig outside the repository (research RS-21).
#
# The rule is first checked against samples, so that a check that sees
# nothing cannot pass for one that finds nothing.
# The samples and the flags are shell text, read and never expanded here.
# shellcheck disable=SC2016,SC1003
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
CDPATH='' cd -- "$root"
# shellcheck disable=SC1091 # lib/command-lines.sh is checked on its own
. local/tests/static/lib/command-lines.sh

local_env="local/scripts/lib/local-env.sh"
kubeconfig_flag='--kubeconfig "$KUBECONFIG_FILE"'
context_flag='--context "$KUBE_CONTEXT"'
name_flag='--name "$CLUSTER_NAME"'

# A word in the position of a command: at the start of a line, of a list of
# tasks ("- "), after a separator, a "$(", a keyword or an assignment.
# "command -v kubectl" and a message that names kubectl are no call.
command_start='(^|[;&|(!{]|\$\(|(then|do|else|exec|time|-) |[A-Za-z_][A-Za-z0-9_]*=[^ ]* ) *'

# check_file FILE: one line per command of FILE that breaks the rule.
check_file() {
  local file="$1" number text rest
  while IFS=$'\t' read -r number text; do
    if [[ $text =~ ${command_start}kubectl( |$) ]]; then
      case "$text" in
        *"kubectl version --client"*) ;;
        *"kubectl kustomize "*)
          rest="${text#*kubectl}"
          case "$rest" in
            *kubectl*) printf '%s:%s: kubectl kustomize with another kubectl on the line: %s\n' "$file" "$number" "$text" ;;
          esac
          ;;
        *"$kubeconfig_flag"*"$context_flag"* | *"$context_flag"*"$kubeconfig_flag"*) ;;
        *) printf '%s:%s: kubectl without %s and %s: %s\n' "$file" "$number" "$kubeconfig_flag" "$context_flag" "$text" ;;
      esac
    fi
    case "$text" in
      *port-forward*)
        if [[ ! $text =~ --address[\ =]127\.0\.0\.1( |$) ]] || [[ $text =~ --address[\ =]([^1]|1[^2]|12[^7]) ]]; then
          printf '%s:%s: port-forward without --address 127.0.0.1 alone: %s\n' "$file" "$number" "$text"
        fi
        ;;
    esac
    if [[ $text =~ ${command_start}kind\ (create\ clusters?|delete\ clusters?|export\ kubeconfig|get\ kubeconfig) ]]; then
      case "$text" in
        *"$kubeconfig_flag"*) ;;
        *) printf '%s:%s: kind writes or removes a kubeconfig entry without %s: %s\n' "$file" "$number" "$kubeconfig_flag" "$text" ;;
      esac
      case "$text" in
        *"$name_flag"*) ;;
        *) printf '%s:%s: kind without %s: %s\n' "$file" "$number" "$name_flag" "$text" ;;
      esac
    fi
    # A global option of docker (--context, -c, --host, -H, --config, ...)
    # aims the command at another engine than the one of the user's current
    # context, which preflight.sh has checked. The tasks and the scripts
    # write no option before the docker command.
    if [[ $text =~ ${command_start}docker\ - ]]; then
      printf '%s:%s: docker with a global option, which can aim it at another engine: %s\n' "$file" "$number" "$text"
    fi
    if [[ $text =~ (^|[^A-Za-z0-9_])KUBECONFIG= ]]; then
      printf '%s:%s: KUBECONFIG set; the tasks pass %s instead: %s\n' "$file" "$number" "$kubeconfig_flag" "$text"
    fi
  done < <(logical_lines "$file")
}

# The samples: each bad one must be caught, the good ones must pass.
samples="$(mktemp -d)"
trap 'rm -rf "${samples:?}"' EXIT
printf '%s\n' \
  'kubectl get pods' \
  'kubectl --kubeconfig "$KUBECONFIG_FILE" get pods' \
  'kubectl --context kind-saas-b2b get pods' \
  'kubectl --kubeconfig "$KUBECONFIG_FILE" --context "$KUBE_CONTEXT" \' \
  '  port-forward svc/api 8080:80' \
  'kubectl --kubeconfig "$KUBECONFIG_FILE" --context "$KUBE_CONTEXT" port-forward --address 0.0.0.0,127.0.0.1 svc/api 8080:80' \
  'kind create cluster --name "$CLUSTER_NAME" --config local/kind/cluster.yaml' \
  'kind delete cluster --kubeconfig "$KUBECONFIG_FILE"' \
  'kind delete clusters --all' \
  'docker --context prod rm x' \
  'docker -H tcp://192.0.2.1:2375 run x' \
  'docker --host=tcp://192.0.2.1:2375 volume rm x' \
  'export KUBECONFIG=/tmp/x' \
  '  - kubectl apply -k k8s/overlays/local' \
  'kubectl kustomize local/k8s/lite | kubectl apply -f -' \
  'kubectl delete namespace saas-b2b; kubectl kustomize local/k8s/lite' >"$samples/bad.sh"
printf '%s\n' \
  '# kubectl get pods, in a comment' \
  'kubectl --kubeconfig "$KUBECONFIG_FILE" --context "$KUBE_CONTEXT" get pods' \
  'kubectl --context "$KUBE_CONTEXT" --kubeconfig "$KUBECONFIG_FILE" \' \
  '  port-forward --address 127.0.0.1 svc/api 8080:80' \
  'out="$(kubectl version --client --output=json 2>/dev/null)"' \
  'kind create cluster --name "$CLUSTER_NAME" --config local/kind/cluster.yaml --kubeconfig "$KUBECONFIG_FILE"' \
  'echo "kubectl.kubernetes.io/last-applied-configuration"' \
  'if ! command -v kubectl >/dev/null 2>&1; then' \
  'refuse "kubectl is not installed: install kubectl 1.36 (README.md)."' \
  'docker info --format "{{.MemTotal}}"' \
  'docker context inspect --format "{{.Name}}"' \
  'if ! command -v docker >/dev/null 2>&1; then' \
  'echo "docker --context is refused"' \
  'rendered="$(kubectl kustomize "local/k8s/$profile")"' >"$samples/good.sh"
bad_found="$(check_file "$samples/bad.sh" | wc -l | tr -d ' ')"
if [ "$bad_found" != 16 ]; then
  echo "the rule caught $bad_found of the 16 findings of the 15 bad samples:" >&2
  check_file "$samples/bad.sh" >&2
  exit 1
fi
good_found="$(check_file "$samples/good.sh")"
if [ -n "$good_found" ]; then
  echo "the rule refused good samples:" >&2
  printf '%s\n' "$good_found" >&2
  exit 1
fi

# The two values and where they point.
if [ ! -f "$local_env" ]; then
  echo "$local_env is missing: it holds the kubeconfig and the context of the local cluster (research RS-21)." >&2
  exit 1
fi
values="$(HOME=/home/s19 bash -c '. "$1" && printf "%s|%s|%s" "$KUBECONFIG_FILE" "$KUBE_CONTEXT" "$CLUSTER_NAME"' s19 "$local_env")"
kubeconfig="${values%%|*}"
values="${values#*|}"
context="${values%%|*}"
cluster="${values#*|}"
if [ "$context" != "kind-$cluster" ] || [ -z "$cluster" ]; then
  echo "$local_env: KUBE_CONTEXT is \"$context\", kind-<cluster> expected for the cluster \"$cluster\"." >&2
  exit 1
fi
case "$kubeconfig" in
  /home/s19/.kube/?*) ;;
  *)
    echo "$local_env: KUBECONFIG_FILE is \"$kubeconfig\", a file under \$HOME/.kube/ expected, outside the repository (research RS-21)." >&2
    exit 1
    ;;
esac

problems=""
while IFS= read -r file; do
  problems="$problems$(check_file "$file")"
done < <(command_files)
if [ -n "$problems" ]; then
  printf '%s\n' "$problems" >&2
  exit 1
fi
echo "Every kubectl and kind call of the tasks and scripts names the kubeconfig of the project and its context."
