# shellcheck shell=bash
# shellcheck disable=SC2034 # the OFFLINE_ values are read by the tests that source this file
# Shared helpers of the tests without a public registry (spec 001, step 10,
# local/tests/offline/). Sourced by each test, never run on its own. It adds
# to lib/e2e.sh of the tests on kind: a copy of the golden repo that a test
# may cut off from the registries, a bounded `task`, a probe of the mirror
# from a pod, a pod in imagePullPolicy: Always and the witness pods.
#
# How the public registries are cut (BENCH-010, tests/bench/bench-010-offline.sh,
# "Offline is simulated in the node only, never on the host"): never the
# network of the machine, never another container. Two files of a copy of the
# golden repo change, between two task up:
# - local/mirror/certs.d/<registry>/hosts.toml gains a `server` line that is a
#   dead end, https://127.0.0.1:9 (nothing listens on the loopback of the
#   node), and local/mirror/certs.d/_default/hosts.toml is the dead end alone
#   for any other registry. containerd uses `server` once every host has been
#   tried (docs/hosts.md), so no pull falls back to the upstream;
# - local/mirror/zot/config.json sends the on-demand sync of zot to the same
#   dead end, since each task up starts a new mirror container that reads it.
# The folder is mounted in the node when kind creates it, so the cut holds for
# the cluster of the next task up and for it alone. The copy keeps the real
# tree untouched, whatever a test does.

OFFLINE_TESTS_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091 # lib/e2e.sh is checked on its own
. "$OFFLINE_TESTS_DIR/../e2e/lib/e2e.sh"

# The dead end of the cut, and the registries of local/mirror/registries.
OFFLINE_DEAD_END="https://127.0.0.1:9"
# How long a task up gets, the first start with the network included, and a
# task up that must fail.
OFFLINE_UP_LIMIT_SECONDS=900
# The pull error that the pull wait of task up reports after
# PULL_ERROR_SECONDS (local/scripts/lib/pull-wait.sh), with the creation of
# the cluster and the steps before it: a first start without a registry must
# fail within this time.
OFFLINE_FAIL_LIMIT_SECONDS=300
# How long a pod gets to end, or to fail its pull.
OFFLINE_POD_WAIT_SECONDS=120
OFFLINE_POD_PAUSE_SECONDS=2
# The pods that prove the cut: images of registries that exist, which no cache
# holds, by digest (BENCH-010, tests/bench/bench-010/witness.yaml, read on
# 2026-11-20). Offline, each pull fails, and the error names the dead end.
OFFLINE_WITNESS_NAMESPACE="e2e-offline-witness"
OFFLINE_WITNESS_DOCKER="docker.io/library/hello-world:latest@sha256:1e4c05b897a751332ce85c7e9449da2d93514ea2dea6dbb0e2753c9e949b2bfa"
OFFLINE_WITNESS_QUAY="quay.io/prometheus/busybox:latest@sha256:7379672d53c28113469275f2eb48adffa19954f39f8ef20c1e2992278f658e6c"
# The digest of the empty JSON, a blob that the requests of the probes name.
OFFLINE_EMPTY_BLOB="sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"

OFFLINE_WORK=""
ELAPSED=0

# offline_work: makes the work folder of the test, removed by the caller's trap.
offline_work() {
  OFFLINE_WORK="$(mktemp -d)" || return 1
}

# offline_copy_repo: copies the golden repo into the work folder and points
# E2E_ROOT at the copy, so that run_task and must_succeed work on it.
offline_copy_repo() {
  local dest="$OFFLINE_WORK/saas-b2b"
  mkdir "$dest" && cp -R "$E2E_ROOT/." "$dest/" || return 1
  E2E_ROOT="$dest"
}

# offline_cut: cuts the public registries in the copy (see the head of this
# file). Fails when a file did not change.
offline_cut() {
  local certs="$E2E_ROOT/local/mirror/certs.d" registry rest hosts config
  while read -r registry rest; do
    case "$registry" in "" | "#"*) continue ;; esac
    hosts="$certs/$registry/hosts.toml"
    [ -f "$hosts" ] || {
      printf 'no %s in the copy\n' "$hosts"
      return 1
    }
    {
      printf 'server = "%s"\n\n' "$OFFLINE_DEAD_END"
      cat "$hosts"
    } >"$hosts.new" && mv "$hosts.new" "$hosts"
    grep -q "^server = \"$OFFLINE_DEAD_END\"" "$hosts" || return 1
  done <"$E2E_ROOT/local/mirror/registries"
  mkdir -p "$certs/_default"
  printf '# Cut: no registry other than the mirror answers.\nserver = "%s"\n' "$OFFLINE_DEAD_END" >"$certs/_default/hosts.toml"
  config="$E2E_ROOT/local/mirror/zot/config.json"
  # Written in place, not replaced: the zot container of the next task up mounts
  # this file, and one run on OrbStack saw zot fail to open a file that mv had
  # replaced ("no such file or directory", tasks.md, gap 164).
  sed 's|"https://[^"]*"|"'"$OFFLINE_DEAD_END"'"|' "$config" >"$config.new" && cat "$config.new" >"$config" && rm -f "$config.new"
  grep -q "\"$OFFLINE_DEAD_END\"" "$config" || return 1
  if grep -q 'index.docker.io' "$config"; then
    return 1
  fi
}

# offline_task LIMIT ARG...: task ARG... in the golden repo, ended after LIMIT
# seconds at most. Sets OUTPUT, STATUS (124 when the limit ended it) and
# ELAPSED. Only task runs in the background: nothing here needs timeout,
# which bash 3.2 and macOS do not have.
offline_task() {
  local limit="$1" pid waited=0 out start="$SECONDS"
  shift
  out="$OFFLINE_WORK/task.out"
  : >"$out"
  (CDPATH='' cd -- "$E2E_ROOT" && exec task "$@") >"$out" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$limit" ]; then
      kill "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      STATUS=124
      OUTPUT="$(cat "$out")"
      ELAPSED=$((SECONDS - start))
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  STATUS=0
  wait "$pid" || STATUS=$?
  OUTPUT="$(cat "$out")"
  ELAPSED=$((SECONDS - start))
}

# up_within LIMIT: task up, bounded; fails the test if it does not succeed.
up_within() {
  offline_task "$1" up
  if [ "$STATUS" -ne 0 ]; then
    fail "task up failed (status $STATUS) after $ELAPSED s"
    show_output
    return 1
  fi
}

# The statuses and bodies that a pod got from the mirror, see mirror_probe.
PROBE=""

# mirror_probe NAMESPACE REQUEST...: sends each REQUEST ("METHOD /path") to
# the mirror from a pod of the namespace NAMESPACE, which this function
# creates under the restricted profile and removes. PROBE then holds, per
# request, "STATUS <request>|<status line>" and, for a GET, "BODY
# <request>|<last line of the answer>". A refusal can close the connection
# while the answer is still coming: each request is asked up to three times.
# Fails when the pod did not run to its end.
mirror_probe() {
  local namespace="$1" request script quoted=""
  shift
  for request in "$@"; do
    quoted="$quoted \"$request\""
  done
  # shellcheck disable=SC2016 # expanded by bash in the pod
  script='connect="exec 3<>/dev/tcp/\$0/5000 && printf \"%s HTTP/1.0\\r\\nHost: %s\\r\\nContent-Length: 0\\r\\n\\r\\n\" \"\$1\" \"\$0\" >&3 && tr -d \"\\r\" <&3"
name="$1"
shift
for request in "$@"; do
  answer=""
  for try in 1 2 3; do
    answer="$(timeout 5 bash -c "$connect" "$name" "$request" 2>/dev/null || true)"
    [ -n "$answer" ] && break
  done
  echo "STATUS $request|$(printf "%s\n" "$answer" | head -n 1)"
  case "$request" in
    GET*) echo "BODY $request|$(printf "%s\n" "$answer" | tail -n 1)" ;;
  esac
done'
  PROBE=""
  client_namespace "$namespace" || {
    fail "could not create the namespace $namespace of the probe of the mirror"
    return 1
  }
  client_pod "$namespace" mirror-probe "set -- $E2E_MIRROR$quoted; $script"
  if [ "$STATUS" -ne 0 ]; then
    fail "the pod that probes the mirror did not run to its end"
    show_output
    remove_client_namespace "$namespace"
    return 1
  fi
  PROBE="$OUTPUT"
  remove_client_namespace "$namespace"
}

# probe_code REQUEST: the status code of REQUEST in PROBE, empty without answer.
probe_code() {
  local line
  line="$(printf '%s\n' "$PROBE" | grep -F -- "STATUS $1|" | head -n 1)"
  [[ $line =~ \|HTTP/1\.[01]\ ([0-9][0-9][0-9]) ]] || return 0
  printf '%s' "${BASH_REMATCH[1]}"
}

# probe_body REQUEST: the last line of the answer to REQUEST in PROBE.
probe_body() {
  printf '%s\n' "$PROBE" | LC_ALL=C awk -v key="BODY $1|" 'index($0, key) == 1 { print substr($0, length(key) + 1); exit }'
}

# always_pod NAMESPACE NAME: a pod on the Postgres image of the stack, by
# digest, in imagePullPolicy: Always, under the restricted profile, that runs
# `true`: the kubelet asks the registry again even though the node holds the
# image (BENCH-010, M4). Waits for it to end, removes it, sets STATUS to 0
# when it succeeded, and OUTPUT to the events of its pull.
always_pod() {
  local namespace="$1" name="$2" image phase="" waited=0 overrides
  image="$(postgres_image)"
  overrides='{"apiVersion":"v1","spec":{"automountServiceAccountToken":false,"securityContext":{"runAsNonRoot":true,"runAsUser":999,"runAsGroup":999,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"'"$name"'","securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'
  STATUS=1
  if ! OUTPUT="$(kube_e2e --namespace "$namespace" run "$name" --image="$image" --image-pull-policy=Always \
    --restart=Never --override-type=strategic --overrides="$overrides" --command -- true 2>&1)"; then
    return 0
  fi
  while :; do
    phase="$(kube_e2e --namespace "$namespace" get pod "$name" --output 'jsonpath={.status.phase}' 2>/dev/null)" || phase=""
    case "$phase" in Succeeded | Failed) break ;; esac
    [ "$waited" -lt "$OFFLINE_POD_WAIT_SECONDS" ] || break
    sleep "$OFFLINE_POD_PAUSE_SECONDS"
    waited=$((waited + OFFLINE_POD_PAUSE_SECONDS))
  done
  OUTPUT="phase=${phase:-none}; $(kube_e2e --namespace "$namespace" get events \
    --field-selector "involvedObject.name=$name" --output 'jsonpath={range .items[*]}{.reason}: {.message}{"; "}{end}' 2>&1)"
  [ "$phase" = Succeeded ] && STATUS=0
  kube_e2e --namespace "$namespace" delete pod "$name" --ignore-not-found --wait=false >/dev/null 2>&1 || :
}

# witness_pull NAME IMAGE: a pod of the witness namespace on IMAGE, which no
# cache holds; waits until the kubelet reports the failure of the pull, then
# prints its message ("-" when none came, "running" when the pod started,
# which means the cut leaks).
witness_pull() {
  local name="$1" image="$2" waited=0 reason="" message=""
  kube_e2e --namespace "$OFFLINE_WITNESS_NAMESPACE" run "$name" --image="$image" --restart=Never >/dev/null 2>&1 || {
    printf 'not created'
    return 0
  }
  while :; do
    reason="$(kube_e2e --namespace "$OFFLINE_WITNESS_NAMESPACE" get pod "$name" \
      --output 'jsonpath={.status.containerStatuses[0].state.waiting.reason}{.status.containerStatuses[0].state.running.startedAt}' 2>/dev/null)" || reason=""
    case "$reason" in
      ErrImagePull | ImagePullBackOff) break ;;
      [0-9]*) printf 'running'; return 0 ;;
    esac
    [ "$waited" -lt "$OFFLINE_POD_WAIT_SECONDS" ] || break
    sleep "$OFFLINE_POD_PAUSE_SECONDS"
    waited=$((waited + OFFLINE_POD_PAUSE_SECONDS))
  done
  message="$(kube_e2e --namespace "$OFFLINE_WITNESS_NAMESPACE" get events \
    --field-selector "involvedObject.name=$name,reason=Failed" \
    --output 'jsonpath={range .items[*]}{.message}{"\n"}{end}' 2>/dev/null | head -n 1)"
  printf '%s' "${message:--}"
}

# mirror_logged_gets REPOSITORY: the number of GET requests of manifests and
# blobs of REPOSITORY that the mirror container logged with a 200. The log of
# zot holds one JSON line per request, with "method", "path" and "statusCode".
mirror_logged_gets() {
  docker logs "$E2E_MIRROR" 2>&1 |
    grep -E "\"method\":\"GET\"" |
    grep -E "\"path\":\"/v2/$1/(manifests|blobs)/" |
    grep -c -E "\"statusCode\":200" || true
}

# image_repositories: the repository, in the form of the catalog of zot, of
# every image of a container that runs in the cluster and comes from a
# registry of local/mirror/registries (library/postgres for the official
# image), one per line, sorted. The namespaces of kind itself are left out:
# kube-system and local-path-storage run images that the node image already
# holds, which no pull brings through the mirror (tasks.md, gap 169).
image_repositories() {
  local registry rest image path
  kube_e2e get pods --all-namespaces --field-selector 'metadata.namespace!=kube-system,metadata.namespace!=local-path-storage' \
    --output 'jsonpath={range .items[*]}{range .spec.initContainers[*]}{.image}{"\n"}{end}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' |
    sort -u |
    while read -r image; do
      [ -n "$image" ] || continue
      while read -r registry rest; do
        case "$registry" in "" | "#"*) continue ;; esac
        case "$image" in
          "$registry"/*)
            path="${image#"$registry"/}"
            path="${path%%@*}"
            path="${path%%:*}"
            printf '%s\n' "$path"
            ;;
        esac
      done <"$E2E_ROOT/local/mirror/registries"
    done | LC_ALL=C sort -u
}
