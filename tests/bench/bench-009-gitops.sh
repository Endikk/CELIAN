#!/usr/bin/env bash
# BENCH-009: GitOps tool of the generated project, measured on kind.
# Options: Argo CD, Flux, and the open source build of Config Sync, each
# installed from its release manifest, checked against a pinned SHA-256, with
# every image rewritten to a pinned digest before use.
#
# Each run creates a fresh kind cluster (kind 0.33.0, node image pinned by
# digest, as in ADR-004) and measures, for one option:
#   - installation until "ready": every Deployment and StatefulSet of the
#     tool ready and every pod Running and Ready, images pulled by the node;
#   - first sync of three environments (local, staging, prod) from one Git
#     repository served inside the cluster, until each one runs its workload;
#   - memory and CPU of the tool's pods at rest, IDLE_WAIT seconds after that
#     sync, from the kubelet Summary API (3 samples, 10 s apart);
#   - propagation of one commit pushed from a pod, after an explicit refresh
#     request when the tool documents one.
# Runs are interleaved (option A, option B, option A, ...). If Config Sync
# does not become ready (its images are x86 only), the failure is recorded
# once and its remaining runs are skipped.
#
# Usage: tests/bench/bench-009-gitops.sh [TRIAL_DIR]
#   TRIAL_DIR, if given, must be missing or empty (default: a new mktemp -d).
#   Environment:
#     OPTIONS="argocd flux configsync"  options, interleaved in this order;
#                       "none" adds the base node: same cluster, Git server
#                       and overlays (applied by kubectl apply -k), no tool
#     RUNS=3            runs per option
#     IDLE_WAIT=120     seconds between the end of the sync and the 1st sample
#     BENCH_LOCK=DIR    optional lock directory shared with other benchmarks:
#                       created with mkdir right after the start-up checks
#                       (exit code 75 if it exists), holds an "owner" file,
#                       removed by the EXIT trap
#     NODE_PLATFORM=    empty by default. "linux/amd64" exports
#                       DOCKER_DEFAULT_PLATFORM, so that kind runs an x86 node
#                       and the test images are built for x86: on an arm64
#                       host this runs under emulation, for functional checks
#                       only (timings and memory are not representative)
#   Results (TSV) in TRIAL_DIR: versions.tsv, manifests.tsv, images.tsv,
#   runs.tsv, idle-pods.tsv, node-images.tsv, functional.tsv, load.tsv,
#   summary.tsv; command output in TRIAL_DIR/logs/.
# Needs: bash >= 3.2, docker (with BuildKit), kind v0.33.0, kubectl (1.35 to
#   1.37), gh, jq, perl, shasum, git, awk.
#
# Safety:
#   - the cluster is named celian-bench-009. The script refuses to start if it
#     already exists. Its EXIT trap is set only after the start-up checks, so a
#     refusal deletes nothing; afterwards it deletes only that cluster;
#   - umask 077; KUBECONFIG points into TRIAL_DIR: ~/.kube is neither read nor
#     written;
#   - no port is published to the host: kind keeps its API on 127.0.0.1 and
#     every test runs from a pod inside the cluster (no curl, no docker run);
#   - images are removed by exact reference only: the two test images this
#     script builds. Base images (alpine, busybox) stay in the Docker cache.
# Side effects outside TRIAL_DIR: the Docker image and build caches, and the
#   "kind" Docker network, removed at the end if the script created it and
#   nothing uses it. The node pulls the tools' images from quay.io, ghcr.io,
#   public.ecr.aws and gcr.io at every run.
set -euo pipefail
umask 077

# --- Pinned versions ----------------------------------------------------------

readonly KIND_VERSION="v0.33.0"
readonly KIND_IMAGE="kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed"
readonly KUBECTL_MINORS="35 36 37"

# Argo CD v3.6.2: manifests/install.yaml at the commit of tag v3.6.2 (the
# "Non-HA" quick start of the release notes). Read on 2026-11-19.
readonly ARGOCD_VERSION="v3.6.2"
readonly ARGOCD_COMMIT="8e8268ef2f3df99ca95663f5080fa6056f156805"
readonly ARGOCD_SHA256="c948064d38294d857712ef78444768749a14293613098932f8533e37d067a2a2"
# Flux v2.10.0: release asset install.yaml (documented "dev install").
readonly FLUX_VERSION="v2.10.0"
readonly FLUX_SHA256="a8c838ccd9be5d30eba9df87cd229b7c4eb80c0049fba1bc3b9840829f267f28"
# Config Sync v1.25.2 (open source build): release asset config-sync-manifest.yaml.
readonly CONFIGSYNC_VERSION="v1.25.2"
readonly CONFIGSYNC_SHA256="bb5cf3cafe4d8a04adbcd900cac709c26dad0d1856fdffdf4c599e4cd4058121"

# Index digest of every image the three manifests name, read on 2026-11-19
# with `docker buildx imagetools inspect`. Each "image: REF" line of a
# verified manifest becomes "image: REF@DIGEST"; an image left without a
# digest stops the script.
readonly IMAGE_PINS="
quay.io/argoproj/argocd:v3.6.2 sha256:bbcc3b6e79c5963439bdc5170f6e20a52365b41878133fac5ce8d6810d2641dc
ghcr.io/dexidp/dex:v2.46.0 sha256:933fcd3f523338c847b88ef84a7145fb2fcb7b9917f08418612afeaaa2001777
public.ecr.aws/docker/library/redis:8.10.1-alpine sha256:ef216d85ec44f4fdf7c0e6df2d1757a4734ed32fbb278cabd3181b5a27353b79
ghcr.io/fluxcd/helm-controller:v1.7.1 sha256:54526cc6ed1202d71d44c310676448065664f3255ad671d9a69ac26f904e617a
ghcr.io/fluxcd/image-automation-controller:v1.3.0 sha256:6ec488320def72fecfd01ab1289cc6c881d76b984fbbcf69b174e1e10886029e
ghcr.io/fluxcd/image-reflector-controller:v1.3.0 sha256:b4d2cbdc1b7a046c53786628fe900b72b31a95c4cec219478777e3f97c453635
ghcr.io/fluxcd/kustomize-controller:v1.10.1 sha256:37db29b25dae35b881a5e064acedb0cc954442da453a39eaa0eab7a90dbecc4e
ghcr.io/fluxcd/notification-controller:v1.10.0 sha256:9f58b9532ec9d3ccf539cd3ccdf283477a5dcb7777b922db5477d8bbd4d3767c
ghcr.io/fluxcd/source-controller:v1.10.1 sha256:611b6bca3eae95bcff471414d1fb14a4ab83d7f14e609cccef2bd389c121f37e
ghcr.io/fluxcd/source-watcher:v2.3.1 sha256:cb94a51b0f7a433fd5610b5f3cd8eb06ba7d70c656a3594dfe19f656ee996d96
gcr.io/config-management-release/gcenode-askpass-sidecar:v1.25.2 sha256:5a5f4ae00462acf27c34694029fe505a4cc8cbd8c0afce8c22bd2c61e7b9d56b
gcr.io/config-management-release/git-sync:v4.5.0-gke.3__linux_amd64 sha256:17bcbc883663e471dfb9db836ed299ae9e14dcd5cfe811c1ec6b3f8ab166ab2c
gcr.io/config-management-release/helm-sync:v1.25.2 sha256:cf923daee784cab355ecaa227dc456821a73f77c4db14081e2962f65f337372e
gcr.io/config-management-release/hydration-controller:v1.25.2 sha256:efe987b9f32464944b50276bd69e21f5fa0386fb5c9560e15d68b557dad3f523
gcr.io/config-management-release/oci-sync:v1.25.2 sha256:152d0e041b7313ac8276806cb840d9d3c82c43ddb574148fb6b9a3f5655b9b94
gcr.io/config-management-release/otelcontribcol:v0.159.0-gke.4 sha256:3e4d301891726c9f11a55267a1fe7467752ce45251c8f41b4f344db869e2aeb5
gcr.io/config-management-release/reconciler-manager:v1.25.2 sha256:c92031c1fff2cdec92e07b24f87d5de591a330121c057a32e19f1b43a5232143
gcr.io/config-management-release/reconciler:v1.25.2 sha256:55e569201329b4fa3fd34d10b85618c20a8aab0ce53932eb82c2303b800da72b
gcr.io/config-management-release/resource-group-controller:v1.25.2 sha256:dc5a7448d2e8c7ec92806793ba028575e8180353aa3297d69abec63854f4b637
"

# Test images, built locally and loaded into the node with kind load.
readonly ALPINE_IMAGE="alpine:3.24@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf"
readonly BUSYBOX_IMAGE="busybox:1.37.0@sha256:a7dbc319b1438115a207e11930dc4bb3e643dcb3ec0bdd694bb36cd8fad289ec"

readonly CLUSTER="celian-bench-009"
readonly NODE="$CLUSTER-control-plane"
readonly GIT_IMAGE="celian-bench-009-git:1"
readonly HELLO_IMAGE="celian-bench-009-hello:1"
readonly REPO_URL="http://git.git-server.svc.cluster.local:8080/git/demo.git"
readonly ENVS="local staging prod"
readonly SAMPLES=3
readonly SAMPLE_GAP=10
readonly PAUSE_BETWEEN_RUNS=15
readonly READY_STREAK=3
readonly CLUSTER_TIMEOUT=300
readonly INSTALL_TIMEOUT=600
readonly CONFIGSYNC_TIMEOUT=300
readonly SYNC_TIMEOUT=300
readonly CHANGE_TIMEOUT=240

OPTIONS="${OPTIONS:-argocd flux configsync}"
RUNS="${RUNS:-3}"
IDLE_WAIT="${IDLE_WAIT:-120}"
BENCH_LOCK="${BENCH_LOCK:-}"
NODE_PLATFORM="${NODE_PLATFORM:-}"
readonly OPTIONS RUNS IDLE_WAIT BENCH_LOCK NODE_PLATFORM

TRIAL_DIR=""
LOGS=""
LOCK_HELD=0
KIND_NETWORK_EXISTED=0
CREATED_IMAGES=""
CONFIGSYNC_SKIP=0
RUN_OK=1

# --- Helpers ------------------------------------------------------------------

log() { printf '[bench-009 %s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die() {
  log "ERROR: $*"
  exit 1
}
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
seconds_between() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", b - a }'; }
utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

tsv() {
  local file=$1
  shift
  local IFS=$'\t'
  printf '%s\n' "$*" >>"$TRIAL_DIR/$file"
}

median_range() {
  sort -n | awk '{ v[NR] = $1 } END {
    if (NR == 0) { print "-\t-"; exit }
    m = (NR % 2) ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2
    printf "%.1f\t%.1f\n", m, v[NR] - v[1] }'
}

kube() { kubectl --request-timeout=20s "$@"; }

# Print the time of the first of READY_STREAK consecutive successes of a
# command, polled every second, or fail after TIMEOUT seconds.
wait_streak() {
  local timeout=$1 deadline streak=0 first="" t
  shift
  deadline=$(($(date +%s) + timeout))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    t=$(now)
    if "$@"; then
      if [ "$streak" -eq 0 ]; then first=$t; fi
      streak=$((streak + 1))
      if [ "$streak" -ge "$READY_STREAK" ]; then
        echo "$first"
        return 0
      fi
    else
      streak=0
    fi
    sleep 1
  done
  return 1
}

# --- Options --------------------------------------------------------------------

option_version() {
  case $1 in
    argocd) echo "$ARGOCD_VERSION" ;;
    flux) echo "$FLUX_VERSION" ;;
    configsync) echo "$CONFIGSYNC_VERSION" ;;
    none) echo "-" ;;
  esac
}

# Namespaces whose pods belong to the tool, the RootSync reconcilers included.
# For the base node ("none"), the test Git server and the demo workloads.
tool_namespaces() {
  case $1 in
    argocd) echo "argocd" ;;
    flux) echo "flux-system" ;;
    configsync) echo "config-management-system config-management-monitoring resource-group-system" ;;
    none) echo "git-server demo-local demo-staging demo-prod" ;;
  esac
}

manifest_file() { echo "$TRIAL_DIR/manifests/$1-pinned.yaml"; }

# Download the release manifest with gh, check its SHA-256, then pin images.
fetch_manifest() {
  local opt=$1 dir="$TRIAL_DIR/manifests" raw expected sum
  mkdir -p "$dir/$opt"
  raw="$dir/$opt/release.yaml"
  case $opt in
    argocd)
      expected=$ARGOCD_SHA256
      gh api -H 'Accept: application/vnd.github.raw' \
        "repos/argoproj/argo-cd/contents/manifests/install.yaml?ref=$ARGOCD_COMMIT" \
        >"$raw" 2>>"$LOGS/manifests.log" || die "argocd: manifest download failed"
      ;;
    flux)
      expected=$FLUX_SHA256
      gh release download "$FLUX_VERSION" -R fluxcd/flux2 -p install.yaml -D "$dir/$opt" \
        >>"$LOGS/manifests.log" 2>&1 || die "flux: manifest download failed"
      mv "$dir/$opt/install.yaml" "$raw"
      ;;
    configsync)
      expected=$CONFIGSYNC_SHA256
      gh release download "$CONFIGSYNC_VERSION" -R GoogleContainerTools/config-sync \
        -p config-sync-manifest.yaml -D "$dir/$opt" >>"$LOGS/manifests.log" 2>&1 ||
        die "configsync: manifest download failed"
      mv "$dir/$opt/config-sync-manifest.yaml" "$raw"
      ;;
  esac
  sum=$(shasum -a 256 "$raw" | awk '{ print $1 }')
  [ "$sum" = "$expected" ] || die "$opt: manifest SHA-256 $sum differs from $expected"
  cp "$raw" "$(manifest_file "$opt")"
  pin_images "$opt" "$(manifest_file "$opt")"
  tsv manifests.tsv "$opt" "$(option_version "$opt")" "$sum" "$(wc -c <"$raw" | tr -d ' ')" \
    "$(manifest_images "$(manifest_file "$opt")" | wc -l | tr -d ' ')"
}

manifest_images() {
  sed -n -E 's/^[[:space:]]*(-[[:space:]]+)?image:[[:space:]]+([^[:space:]]+)[[:space:]]*$/\2/p' "$1" | sort -u
}

pin_images() {
  local opt=$1 file=$2 ref digest unpinned
  while read -r ref digest; do
    [ -n "$ref" ] || continue
    REF=$ref PIN="$ref@$digest" perl -pi -e \
      's/^(\s*(?:-\s+)?image:\s+)\Q$ENV{REF}\E\s*$/$1$ENV{PIN}\n/' "$file"
  done <<EOF
$IMAGE_PINS
EOF
  unpinned=$(manifest_images "$file" | grep -v '@sha256:' || true)
  [ -z "$unpinned" ] || die "$opt: images without a pinned digest: $(printf '%s' "$unpinned" | paste -sd, -)"
}

install_tool() {
  local opt=$1 file
  file=$(manifest_file "$opt")
  case $opt in
    argocd)
      kubectl create namespace argocd &&
        kubectl apply -n argocd --server-side --force-conflicts -f "$file"
      ;;
    flux | configsync) kubectl apply -f "$file" ;;
    none) echo "base node: no GitOps tool installed" ;;
  esac
}

# Ask the tool to sync the three overlays. The base node gets the same
# overlays applied directly, with the kustomize built into kubectl.
apply_sync() {
  local opt=$1 env
  if [ "$opt" = none ]; then
    for env in $ENVS; do
      kubectl apply -k "$TRIAL_DIR/repo-src/apps/demo/overlays/$env" || return 1
    done
    return 0
  fi
  sync_objects "$opt" | kube apply -f -
}

# jq filter: every Deployment and StatefulSet of the namespace is ready, and
# every pod is Running and Ready (or Succeeded).
# shellcheck disable=SC2016 # jq variables, not shell ones
readonly WORKLOADS_READY='
  [.items[] | select(.kind == "Deployment" or .kind == "StatefulSet")] as $w
  | [.items[] | select(.kind == "Pod")] as $p
  | ($w | length) > 0
  and all($w[]; (.status.readyReplicas // 0) >= (.spec.replicas // 1)
      and (.status.updatedReplicas // 0) >= (.spec.replicas // 1))
  and all($p[]; .status.phase == "Succeeded"
      or (.status.phase == "Running"
          and any(.status.conditions[]?; .type == "Ready" and .status == "True")))'

tool_ready() {
  local opt=$1 ns json
  # Nothing to wait for on the base node: the Git server is already ready.
  [ "$opt" != none ] || return 0
  for ns in $(tool_namespaces "$opt"); do
    json=$(kube get deployments,statefulsets,pods -n "$ns" -o json 2>/dev/null) || return 1
    printf '%s' "$json" | jq -e "$WORKLOADS_READY" >/dev/null || return 1
  done
}

# Objects that ask the tool to sync the three overlays of the test repository.
sync_objects() {
  local env
  case $1 in
    argocd)
      cat <<EOF
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: demo
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - list:
        elements:
          - env: local
          - env: staging
          - env: prod
  template:
    metadata:
      name: 'demo-{{.env}}'
    spec:
      project: default
      source:
        repoURL: $REPO_URL
        targetRevision: main
        path: 'apps/demo/overlays/{{.env}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: 'demo-{{.env}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
EOF
      ;;
    flux)
      cat <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: demo
  namespace: flux-system
spec:
  interval: 1m
  url: $REPO_URL
  ref:
    branch: main
EOF
      for env in $ENVS; do
        cat <<EOF
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: demo-$env
  namespace: flux-system
spec:
  interval: 10m
  path: ./apps/demo/overlays/$env
  prune: true
  sourceRef:
    kind: GitRepository
    name: demo
  timeout: 2m
EOF
      done
      ;;
    configsync)
      for env in $ENVS; do
        cat <<EOF
---
apiVersion: configsync.gke.io/v1beta1
kind: RootSync
metadata:
  name: demo-$env
  namespace: config-management-system
spec:
  sourceFormat: unstructured
  git:
    repo: $REPO_URL
    branch: main
    dir: apps/demo/overlays/$env
    auth: none
EOF
      done
      ;;
  esac
}

# Ask for an immediate refresh after a push, when the tool documents one.
request_refresh() {
  case $1 in
    argocd) kube annotate application demo-local -n argocd argocd.argoproj.io/refresh=normal --overwrite ;;
    flux) kube annotate gitrepository demo -n flux-system "reconcile.fluxcd.io/requestedAt=$(date +%s)" --overwrite ;;
    configsync) echo "no refresh request: Config Sync polls the source" ;;
  esac
}

refresh_command() {
  case $1 in
    argocd) echo "annotate application demo-local argocd.argoproj.io/refresh=normal" ;;
    flux) echo "annotate gitrepository demo reconcile.fluxcd.io/requestedAt" ;;
    configsync) echo "none, polling" ;;
  esac
}

# --- Test repository and images -------------------------------------------------

write_file() {
  local path=$1
  mkdir -p "$(dirname "$path")"
  cat >"$path"
}

# One application, a base and three overlays: the layout Q6 asks for.
make_repo() {
  local src="$TRIAL_DIR/repo-src" env
  write_file "$src/apps/demo/base/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
EOF
  write_file "$src/apps/demo/base/deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello
spec:
  replicas: 1
  selector:
    matchLabels: {app: hello}
  template:
    metadata:
      labels: {app: hello}
    spec:
      containers:
        - name: hello
          image: $HELLO_IMAGE
          imagePullPolicy: Never
          ports: [{containerPort: 8080}]
EOF
  for env in $ENVS; do
    write_file "$src/apps/demo/overlays/$env/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: demo-$env
resources:
  - namespace.yaml
  - settings.yaml
  - ../../base
EOF
    write_file "$src/apps/demo/overlays/$env/namespace.yaml" <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: demo-$env
EOF
    write_file "$src/apps/demo/overlays/$env/settings.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: demo-settings
data:
  environment: $env
  revision: "1"
EOF
  done
  git -C "$src" -c init.defaultBranch=main init -q
  git -C "$src" add -A
  git -C "$src" -c user.name=celian-bench -c user.email=bench@example.invalid \
    -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m "demo: three environments"
}

build_images() {
  local dir="$TRIAL_DIR/images"
  make_repo
  mkdir -p "$dir/git" "$dir/hello"
  git clone -q --bare "$TRIAL_DIR/repo-src" "$dir/git/demo.git"
  git -C "$dir/git/demo.git" config http.receivepack true
  # lighttpd configuration from the git-http-backend manual (lighttpd example).
  cat >"$dir/git/git.conf" <<'EOF'
server.document-root = "/srv/git"
server.port = 8080
server.modules = ( "mod_setenv", "mod_alias", "mod_cgi" )
alias.url = ( "/git" => "/usr/libexec/git-core/git-http-backend" )
$HTTP["url"] =~ "^/git" {
  cgi.assign = ( "" => "" )
  setenv.add-environment = (
    "GIT_PROJECT_ROOT" => "/srv/git",
    "GIT_HTTP_EXPORT_ALL" => ""
  )
}
EOF
  # The Service may take a few seconds to route after the pod is ready: the
  # first contact is retried for up to 60 s.
  cat >"$dir/git/ls-remote.sh" <<'EOF'
#!/bin/sh
set -eu
i=0
until git ls-remote "$1" refs/heads/main; do
  i=$((i + 1))
  [ "$i" -lt 60 ] || exit 1
  sleep 1
done
EOF
  cat >"$dir/git/push-change.sh" <<'EOF'
#!/bin/sh
set -eu
i=0
until git clone -q "$1" "/tmp/work-$i"; do
  i=$((i + 1))
  [ "$i" -lt 60 ] || exit 1
  sleep 1
done
cd "/tmp/work-$i"
sed -i 's/revision: "1"/revision: "2"/' apps/demo/overlays/local/settings.yaml
git -c user.name=celian-bench -c user.email=bench@example.invalid commit -q -am "demo: change local revision"
git push -q origin HEAD:main
git rev-parse HEAD
EOF
  cat >"$dir/git/Dockerfile" <<EOF
FROM $ALPINE_IMAGE
RUN apk add --no-cache git git-daemon lighttpd \\
 && test -x /usr/libexec/git-core/git-http-backend
COPY git.conf /etc/lighttpd/git.conf
COPY ls-remote.sh push-change.sh /usr/local/bin/
COPY --chown=65534:65534 demo.git /srv/git/demo.git
USER 65534
ENV HOME=/tmp
EXPOSE 8080
CMD ["lighttpd", "-D", "-f", "/etc/lighttpd/git.conf"]
EOF
  printf '%s\n' "celian-bench-009 ok" >"$dir/hello/index.html"
  cat >"$dir/hello/Dockerfile" <<EOF
FROM $BUSYBOX_IMAGE
COPY index.html /www/index.html
USER 65534
EXPOSE 8080
CMD ["httpd", "-f", "-p", "8080", "-h", "/www"]
EOF
  # umask 077 would hide these files from the unprivileged user of the images.
  chmod -R a+rX "$dir"
  chmod 755 "$dir/git/ls-remote.sh" "$dir/git/push-change.sh"
  docker build -q -t "$GIT_IMAGE" "$dir/git" >>"$LOGS/build.log" 2>&1 || die "git image build failed"
  CREATED_IMAGES="$CREATED_IMAGES $GIT_IMAGE"
  docker build -q -t "$HELLO_IMAGE" "$dir/hello" >>"$LOGS/build.log" 2>&1 || die "hello image build failed"
  CREATED_IMAGES="$CREATED_IMAGES $HELLO_IMAGE"
}

git_server_manifest() {
  cat <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: git-server
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: git
  namespace: git-server
spec:
  replicas: 1
  selector:
    matchLabels: {app: git}
  template:
    metadata:
      labels: {app: git}
    spec:
      containers:
        - name: git
          image: $GIT_IMAGE
          imagePullPolicy: Never
          ports: [{containerPort: 8080}]
          readinessProbe:
            tcpSocket: {port: 8080}
            periodSeconds: 1
---
apiVersion: v1
kind: Service
metadata:
  name: git
  namespace: git-server
spec:
  selector: {app: git}
  ports: [{port: 8080, targetPort: 8080}]
EOF
}

# A Job of the git image, run from inside the cluster.
git_job() {
  local name=$1 script=$2
  cat <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: $name
  namespace: git-server
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: git
          image: $GIT_IMAGE
          imagePullPolicy: Never
          command: ["/usr/local/bin/$script", "$REPO_URL"]
EOF
}

job_state() {
  kube get job "$1" -n git-server -o jsonpath='{.status.succeeded}/{.status.failed}' 2>/dev/null || true
}

# Run a git Job and print the time it is seen complete (polled every 0.5 s).
run_git_job() {
  local name=$1 script=$2 log_file=$3 deadline state
  git_job "$name" "$script" | kube apply -f - >>"$log_file" 2>&1
  deadline=$(($(date +%s) + 120))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    state=$(job_state "$name")
    case $state in
      1/*)
        kube logs "job/$name" -n git-server >>"$log_file" 2>&1 || true
        now
        return 0
        ;;
      */1)
        kube logs "job/$name" -n git-server >>"$log_file" 2>&1 || true
        kube logs deployment/git -n git-server >>"$log_file" 2>&1 || true
        return 1
        ;;
    esac
    sleep 0.5
  done
  return 1
}

# --- Cluster ----------------------------------------------------------------------

# shellcheck disable=SC2016 # jq variables, not shell ones
readonly KUBE_SYSTEM_READY='
  [.items[] | select(.kind == "Pod")] as $pods
  | ($pods | length) > 0
  and all($pods[]; .status.phase == "Succeeded"
      or (.status.phase == "Running"
          and any(.status.conditions[]?; .type == "Ready" and .status == "True")))
  and all(.items[] | select(.kind == "Deployment");
      (.status.availableReplicas // 0) >= .spec.replicas)
  and all(.items[] | select(.kind == "DaemonSet");
      (.status.desiredNumberScheduled // 0) > 0
      and (.status.numberReady // 0) >= .status.desiredNumberScheduled)'

cluster_ready() {
  local json
  json=$(kube get nodes -o json 2>/dev/null) || return 1
  printf '%s' "$json" | jq -e 'all(.items[]; any(.status.conditions[]?; .type == "Ready" and .status == "True"))' >/dev/null || return 1
  json=$(kube get pods,deployments,daemonsets -n kube-system -o json 2>/dev/null) || return 1
  printf '%s' "$json" | jq -e "$KUBE_SYSTEM_READY" >/dev/null
}

cluster_exists() { kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; }

create_cluster() {
  kind create cluster --name "$CLUSTER" --image "$KIND_IMAGE" --kubeconfig "$KUBECONFIG"
}

delete_cluster() { kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG"; }

envs_synced() {
  local env
  for env in $ENVS; do
    [ "$(kube get configmap demo-settings -n "demo-$env" -o jsonpath='{.data.revision}' 2>/dev/null)" = 1 ] || return 1
    [ "$(kube get deployment hello -n "demo-$env" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = 1 ] || return 1
  done
}

change_synced() {
  [ "$(kube get configmap demo-settings -n demo-local -o jsonpath='{.data.revision}' 2>/dev/null)" = 2 ]
}

# --- Records ----------------------------------------------------------------------

record_load() {
  local opt=$1 phase=$2 loadavg total
  loadavg=$(uptime | sed -e 's/.*load average[s]*: //' -e 's/,//g')
  total=$(docker ps -q | wc -l | tr -d ' ')
  tsv load.tsv "$(utc_now)" "$opt" "$phase" "$loadavg" "$total"
}

to_mib_awk='function to_mib(v,  n, u) {
  n = v; sub(/[A-Za-z]+$/, "", n); u = v; sub(/^[0-9.]+/, "", u)
  if (u == "B") return n / 1048576
  if (u == "KiB" || u == "kB") return n / 1024
  if (u == "MiB" || u == "MB") return n
  if (u == "GiB" || u == "GB") return n * 1024
  return -1 }'

# One sample: memory working set and CPU of every pod of the tool, from the
# kubelet Summary API, plus the whole node container from docker stats.
# Prints "tool_mem_mib<TAB>tool_cpu_pct<TAB>node_mem_mib<TAB>node_cpu_pct".
idle_sample() {
  local opt=$1 run=$2 sample=$3 summary pods node_stats
  summary=$(kube get --raw "/api/v1/nodes/$NODE/proxy/stats/summary") || die "summary API unreachable"
  pods=$(printf '%s' "$summary" | jq -r --arg nss "$(tool_namespaces "$opt")" '
    ($nss | split(" ")) as $n
    | .pods[] | select(.podRef.namespace as $x | any($n[]; . == $x))
    | [.podRef.namespace, .podRef.name, ((.memory.workingSetBytes // 0) / 1048576),
       ((.cpu.usageNanoCores // 0) / 10000000)] | @tsv')
  printf '%s\n' "$pods" | awk -F'\t' -v o="$opt" -v r="$run" -v s="$sample" \
    'NF == 4 { printf "%s\t%s\t%s\t%s\t%s\t%.1f\t%.2f\n", o, r, s, $1, $2, $3, $4 }' \
    >>"$TRIAL_DIR/idle-pods.tsv"
  node_stats=$(docker stats --no-stream --format '{{.CPUPerc}}\t{{.MemUsage}}' "$NODE" |
    awk -F'\t' "$to_mib_awk"'{ cpu = $1; sub(/%/, "", cpu); split($2, m, " "); printf "%.1f\t%.2f", to_mib(m[1]), cpu }')
  printf '%s\n' "$pods" | awk -F'\t' -v node="$node_stats" \
    'NF == 4 { m += $3; c += $4 } END { printf "%.1f\t%.2f\t%s\n", m, c, node }'
}

# Images the node pulled during the run, from the Pulled events.
record_pulls() {
  local opt=$1 run=$2
  kube get events -A -o json | jq -r '.items[] | select(.reason == "Pulled") | .message' |
    sed -n -e 's/^Successfully pulled image "\([^"]*\)" in \([^ ]*\) .*/pulled|\1|\2/p' \
      -e 's/^Container image "\([^"]*\)" already present.*/present|\1|-/p' |
    sort -u | while IFS='|' read -r status image took; do
      tsv node-images.tsv "$opt" "$run" "$status" "$image" "$took"
    done
}

restarts() {
  local opt=$1 ns total=0 n
  for ns in $(tool_namespaces "$opt"); do
    n=$(kube get pods -n "$ns" -o json | jq '[.items[].status.containerStatuses[]?.restartCount] | add // 0')
    total=$((total + n))
  done
  echo "$total"
}

# Compressed size per architecture (layers plus config) of every image of an
# option, from the registry manifest: no pull, no container.
record_images() {
  local opt=$1 ref repo_tag sizes try
  for ref in $(manifest_images "$(manifest_file "$opt")"); do
    # "repo:tag@sha256:x" is queried as "repo@sha256:x"; one retry, since a
    # registry can fail a query now and then.
    repo_tag=${ref%@*}
    sizes=""
    for try in 1 2; do
      sizes=$(registry_sizes "${repo_tag%:*}@${ref#*@}")
      [ -z "$sizes" ] || break
      log "$opt: no size for $ref (try $try)"
      sleep 5
    done
    tsv images.tsv "$opt" "$ref" "${sizes:--}"
  done
}

registry_sizes() {
  docker manifest inspect -v "$1" 2>/dev/null | jq -r '
    [if type == "array" then .[] else . end
     | select((.Descriptor.platform.os // "linux") == "linux")
     | (.SchemaV2Manifest // .OCIManifest) as $m
     | "\(.Descriptor.platform.architecture)=\(([$m.layers[]?.size] | add) + ($m.config.size // 0))"]
    | map(select(startswith("arm64=") or startswith("amd64="))) | join(",")' 2>/dev/null || true
}

# Why a tool did not become ready: pod states and warning events.
record_failure() {
  local opt=$1 log_file=$2 ns reasons
  for ns in $(tool_namespaces "$opt"); do
    kube get pods -n "$ns" -o wide >>"$log_file" 2>&1 || true
  done
  kube get events -A --field-selector type=Warning -o json 2>/dev/null |
    jq -r '.items[] | "\(.involvedObject.namespace)/\(.involvedObject.name): \(.reason): \(.message)"' \
      >>"$log_file" 2>&1 || true
  reasons=$(kube get events -A --field-selector type=Warning -o json 2>/dev/null |
    jq -r '[.items[] | .message | select(test("platform|exec format|ErrImagePull|BackOff"; "i"))
      | .[0:160]] | unique | .[0:3] | join(" || ")' 2>/dev/null || true)
  tsv functional.tsv "$opt" install-ready no "${reasons:-see $log_file}"
}

# --- One run --------------------------------------------------------------------

timed_run() {
  local opt=$1 run=$2 log_file started t0 t1 t_ready t_create t_cluster t_s0 t_synced
  local t_push t_changed samples="" i sample mem cpu node_mem node_cpu sync_s change_s
  log_file="$LOGS/$opt-run-$run.log"
  record_load "$opt" "run-$run"
  started=$(utc_now)
  log "$opt run $run: create cluster"
  t_create=$(now)
  create_cluster >"$log_file" 2>&1 || die "$opt run $run: kind create failed, see $log_file"
  t_cluster=$(wait_streak "$CLUSTER_TIMEOUT" cluster_ready) || die "$opt run $run: cluster not ready"
  kind load docker-image "$GIT_IMAGE" "$HELLO_IMAGE" --name "$CLUSTER" >>"$log_file" 2>&1 ||
    die "$opt run $run: kind load failed"
  git_server_manifest | kube apply -f - >>"$log_file" 2>&1
  kubectl rollout status deployment/git -n git-server --timeout=120s >>"$log_file" 2>&1 ||
    die "$opt run $run: git server not ready"
  run_git_job ls-remote ls-remote.sh "$log_file" >/dev/null || die "$opt run $run: git ls-remote from a pod failed, see $log_file"

  log "$opt run $run: install $(option_version "$opt")"
  t0=$(now)
  install_tool "$opt" >>"$log_file" 2>&1 || die "$opt run $run: install failed, see $log_file"
  t1=$(now)
  local timeout=$INSTALL_TIMEOUT
  if [ "$opt" = configsync ]; then timeout=$CONFIGSYNC_TIMEOUT; fi
  if ! t_ready=$(wait_streak "$timeout" tool_ready "$opt"); then
    log "$opt run $run: not ready after ${timeout}s"
    record_failure "$opt" "$log_file"
    record_pulls "$opt" "$run"
    tsv runs.tsv "$opt" "$run" "$started" "$(seconds_between "$t_create" "$t_cluster")" \
      "$(seconds_between "$t0" "$t1")" not-ready - - - - - - "$(restarts "$opt")"
    delete_cluster >>"$log_file" 2>&1 || die "$opt run $run: delete failed"
    RUN_OK=0
    return 0
  fi
  log "$opt run $run: ready in $(seconds_between "$t0" "$t_ready") s"

  t_s0=$(now)
  apply_sync "$opt" >>"$log_file" 2>&1 || die "$opt run $run: sync objects rejected"
  if t_synced=$(wait_streak "$SYNC_TIMEOUT" envs_synced); then
    sync_s=$(seconds_between "$t_s0" "$t_synced")
    log "$opt run $run: three environments synced in $sync_s s"
  else
    sync_s=timeout
    log "$opt run $run: environments not synced after ${SYNC_TIMEOUT}s"
  fi

  sleep "$IDLE_WAIT"
  for i in $(seq 1 "$SAMPLES"); do
    sample=$(idle_sample "$opt" "$run" "$i")
    samples="$samples$sample"$'\n'
    if [ "$i" -lt "$SAMPLES" ]; then sleep "$SAMPLE_GAP"; fi
  done
  mem=$(printf '%s' "$samples" | cut -f1 | grep . | median_range | cut -f1)
  cpu=$(printf '%s' "$samples" | cut -f2 | grep . | median_range | cut -f1)
  node_mem=$(printf '%s' "$samples" | cut -f3 | grep . | median_range | cut -f1)
  node_cpu=$(printf '%s' "$samples" | cut -f4 | grep . | median_range | cut -f1)

  change_s=skipped
  # No commit test on the base node: nothing would pick the commit up.
  if [ "$sync_s" != timeout ] && [ "$opt" != none ]; then
    if t_push=$(run_git_job push-change push-change.sh "$log_file"); then
      request_refresh "$opt" >>"$log_file" 2>&1 || log "$opt run $run: refresh request failed"
      if t_changed=$(wait_streak "$CHANGE_TIMEOUT" change_synced); then
        change_s=$(seconds_between "$t_push" "$t_changed")
      else
        change_s=timeout
      fi
      log "$opt run $run: commit applied after $change_s s ($(refresh_command "$opt"))"
    else
      change_s=push-failed
    fi
  fi

  record_pulls "$opt" "$run"
  tsv runs.tsv "$opt" "$run" "$started" "$(seconds_between "$t_create" "$t_cluster")" \
    "$(seconds_between "$t0" "$t1")" "$(seconds_between "$t0" "$t_ready")" "$sync_s" \
    "$mem" "$cpu" "$node_mem" "$node_cpu" "$change_s" "$(restarts "$opt")"
  log "$opt run $run: delete cluster"
  delete_cluster >>"$log_file" 2>&1 || die "$opt run $run: delete failed"
}

# --- Start-up checks --------------------------------------------------------------

check_versions() {
  local v
  for v in docker kind kubectl gh jq perl shasum git awk; do
    command -v "$v" >/dev/null || die "$v not found"
  done
  v=$(kind version | awk '{ print $2 }')
  [ "$v" = "$KIND_VERSION" ] || die "kind $v found, $KIND_VERSION expected"
  tsv versions.tsv kind "$v"
  v=$(kubectl version --client -o json | jq -r '.clientVersion.minor' | tr -dc '0-9')
  case " $KUBECTL_MINORS " in
    *" $v "*) ;;
    *) die "kubectl 1.$v is more than one minor away from the node image" ;;
  esac
  tsv versions.tsv kubectl "$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion')"
  tsv versions.tsv node-image "$KIND_IMAGE"
  tsv versions.tsv docker "$(docker version --format '{{.Server.Version}}')"
  tsv versions.tsv engine "$(docker info --format '{{.OperatingSystem}} {{.Architecture}} {{.NCPU}} CPU {{.MemTotal}} B cgroup v{{.CgroupVersion}}')"
  tsv versions.tsv host "$(sysctl -n hw.model 2>/dev/null || uname -m) $(sw_vers -productVersion 2>/dev/null || uname -r)"
  for v in $OPTIONS; do
    case $v in
      argocd | flux | configsync | none) tsv versions.tsv "$v" "$(option_version "$v")" ;;
      *) die "unknown option: $v" ;;
    esac
  done
  case $NODE_PLATFORM in
    "") tsv versions.tsv node-platform "engine default" ;;
    linux/amd64 | linux/arm64)
      export DOCKER_DEFAULT_PLATFORM="$NODE_PLATFORM"
      tsv versions.tsv node-platform "$NODE_PLATFORM (DOCKER_DEFAULT_PLATFORM)"
      ;;
    *) die "NODE_PLATFORM must be empty, linux/amd64 or linux/arm64" ;;
  esac
}

acquire_lock() {
  [ -n "$BENCH_LOCK" ] || return 0
  if ! mkdir "$BENCH_LOCK" 2>/dev/null; then
    echo "lock $BENCH_LOCK is held: $(cat "$BENCH_LOCK/owner" 2>/dev/null || echo unknown owner)" >&2
    exit 75
  fi
  LOCK_HELD=1
  printf 'BENCH-009 %s\n' "$(utc_now)" >"$BENCH_LOCK/owner"
}

release_lock() {
  if [ "$LOCK_HELD" = 1 ]; then
    rm -f "$BENCH_LOCK/owner"
    rmdir "$BENCH_LOCK" 2>/dev/null || log "lock $BENCH_LOCK not empty, left in place"
    LOCK_HELD=0
  fi
}

# --- Cleanup ----------------------------------------------------------------------

cleanup() {
  local rc=$? ref
  trap - EXIT INT TERM
  set +e
  if cluster_exists; then
    log "cleanup: deleting the kind cluster $CLUSTER"
    delete_cluster >>"$LOGS/cleanup.log" 2>&1
  fi
  for ref in $CREATED_IMAGES; do
    docker image rm "$ref" >>"$LOGS/cleanup.log" 2>&1 || log "could not remove $ref"
  done
  if [ "$KIND_NETWORK_EXISTED" = 0 ] && docker network inspect kind >/dev/null 2>&1 &&
    [ "$(docker network inspect kind --format '{{len .Containers}}')" = 0 ]; then
    log "cleanup: removing the kind network created by this run"
    docker network rm kind >>"$LOGS/cleanup.log" 2>&1
  fi
  release_lock
  log "results in $TRIAL_DIR"
  exit "$rc"
}

# --- Summary ----------------------------------------------------------------------

summarize() {
  local opt column name values
  tsv summary.tsv option metric runs values median range
  for opt in $OPTIONS; do
    for column in 6:ready_s 7:sync_s 8:tool_mem_mib 9:tool_cpu_pct 10:node_mem_mib 12:change_s 4:cluster_s; do
      name=${column#*:}
      values=$(awk -F'\t' -v o="$opt" -v c="${column%%:*}" \
        '$1 == o && $2 != "run" && $c ~ /^[0-9.]+$/ { print $c }' "$TRIAL_DIR/runs.tsv")
      tsv summary.tsv "$opt" "$name" "$(printf '%s\n' "$values" | grep -c . || true)" \
        "$(printf '%s\n' "$values" | paste -sd, -)" "$(printf '%s\n' "$values" | grep . | median_range)"
    done
  done
}

# --- Main -------------------------------------------------------------------------

main() {
  local opt run
  if [ $# -gt 0 ]; then
    TRIAL_DIR=$1
    if [ -e "$TRIAL_DIR" ] && [ -n "$(ls -A "$TRIAL_DIR")" ]; then
      echo "TRIAL_DIR must be missing or empty: $TRIAL_DIR" >&2
      exit 2
    fi
    mkdir -p "$TRIAL_DIR"
  else
    TRIAL_DIR=$(mktemp -d)
  fi
  TRIAL_DIR=$(cd "$TRIAL_DIR" && pwd)
  LOGS="$TRIAL_DIR/logs"
  mkdir -p "$LOGS"
  export KUBECONFIG="$TRIAL_DIR/kubeconfig"
  : >"$KUBECONFIG"
  chmod 600 "$KUBECONFIG"

  tsv versions.tsv item version
  tsv manifests.tsv option version sha256 bytes images
  tsv images.tsv option image compressed_bytes
  tsv runs.tsv option run started_utc cluster_s install_cmd_s ready_s sync_s \
    tool_mem_mib tool_cpu_pct node_mem_mib node_cpu_pct change_s restarts
  tsv idle-pods.tsv option run sample namespace pod mem_mib cpu_pct
  tsv node-images.tsv option run status image took
  tsv functional.tsv option check result detail
  tsv load.tsv utc option phase loadavg_1_5_15 running_containers

  # Start-up checks first, without any trap: a refusal deletes nothing.
  check_versions
  cluster_exists && die "a kind cluster named $CLUSTER already exists"
  if docker network inspect kind >/dev/null 2>&1; then KIND_NETWORK_EXISTED=1; fi
  acquire_lock
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  log "trial directory: $TRIAL_DIR"

  for opt in $OPTIONS; do
    [ "$opt" != none ] || continue
    fetch_manifest "$opt"
    record_images "$opt"
  done
  build_images

  run=1
  while [ "$run" -le "$RUNS" ]; do
    for opt in $OPTIONS; do
      if [ "$opt" = configsync ] && [ "$CONFIGSYNC_SKIP" = 1 ]; then continue; fi
      # Called outside any "if", so that set -e stays active inside.
      RUN_OK=1
      timed_run "$opt" "$run"
      if [ "$RUN_OK" = 0 ]; then
        [ "$opt" = configsync ] || die "$opt run $run: not ready"
        CONFIGSYNC_SKIP=1
        log "configsync: not ready, remaining runs skipped"
      fi
      sleep "$PAUSE_BETWEEN_RUNS"
    done
    run=$((run + 1))
  done
  summarize
  column -t -s "$(printf '\t')" "$TRIAL_DIR/summary.tsv" >&2 || true
}

main "$@"
