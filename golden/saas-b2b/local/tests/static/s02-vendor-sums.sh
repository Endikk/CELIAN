#!/usr/bin/env bash
# control: S02
# carries: FR-008; ADR-004, condition 4; ADR-005, condition 1
#
# The third-party manifests of the local layer live in local/vendor/, each
# with its SHA-256 in local/vendor/SHA256SUMS, checked before anything is
# applied, and nothing is applied from a URL (ADR-004, condition 4):
# - every file of local/vendor/ but SHA256SUMS has one line there, every
#   line names a file that exists, and every sum matches;
# - local/scripts/platform.sh checks the sums before it calls kubectl: run
#   on a copy of the layer with one byte added, an unlisted file or a
#   listed file gone, against a simulated kubectl that logs every call, it
#   refuses, names the file and calls kubectl not once; on the intact copy,
#   its check passes, still without kubectl;
# - no command of the tasks and of the scripts applies, creates or replaces
#   from a URL.
# The URL rule is first checked against samples.
# The samples are shell text, read and never expanded here.
# shellcheck disable=SC2016,SC1003
set -uo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
CDPATH='' cd -- "$root" || exit 2
# shellcheck disable=SC1091 # lib/command-lines.sh is checked on its own
. local/tests/static/lib/command-lines.sh

vendor="local/vendor"
sums_file="$vendor/SHA256SUMS"
platform_script="local/scripts/platform.sh"
fake_kubectl="local/tests/preflight/fakes/kubectl"
failures=0

fail() {
  failures=$((failures + 1))
  printf '%s\n' "$1" >&2
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

# --- Sums of the vendored files ------------------------------------------------

if [ ! -f "$sums_file" ]; then
  echo "$sums_file is missing: the vendored manifests of the platform are not there yet (spec 001, T058)." >&2
  exit 1
fi

listed=""
line_number=0
while IFS= read -r line || [ -n "$line" ]; do
  line_number=$((line_number + 1))
  if ! [[ $line =~ ^([0-9a-f]{64})\ \ ([A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*)$ ]]; then
    fail "$sums_file, line $line_number: \"$line\" is not \"<sha256>  <path under $vendor/>\"."
    continue
  fi
  sum="${BASH_REMATCH[1]}"
  file="${BASH_REMATCH[2]}"
  case "/$file/" in
    */../* | */./*)
      fail "$sums_file, line $line_number: $file leaves $vendor/."
      continue
      ;;
  esac
  listed="$listed$file"$'\n'
  if [ ! -f "$vendor/$file" ]; then
    fail "$sums_file, line $line_number: $vendor/$file is listed but missing."
  elif [ "$(sha256_of "$vendor/$file")" != "$sum" ]; then
    fail "$vendor/$file: its SHA-256 is $(sha256_of "$vendor/$file"), $sums_file says $sum."
  fi
done <"$sums_file"

present="$(CDPATH='' cd -- "$vendor" && find . -type f ! -path ./SHA256SUMS | sed 's|^\./||' | LC_ALL=C sort)"
if [ -z "$present" ]; then
  fail "$vendor/ holds no manifest besides SHA256SUMS."
fi
duplicates="$(printf '%s' "$listed" | LC_ALL=C sort | uniq -d)"
[ -z "$duplicates" ] || fail "$sums_file lists these files more than once: $(printf '%s' "$duplicates" | tr '\n' ' ')"
unlisted="$(LC_ALL=C comm -23 <(printf '%s\n' "$present") <(printf '%s' "$listed" | LC_ALL=C sort -u) | grep . || true)"
[ -z "$unlisted" ] || fail "Files of $vendor/ without a line in $sums_file: $(printf '%s' "$unlisted" | tr '\n' ' ')"

# --- No application from a URL --------------------------------------------------

# url_applies FILE: one line per command of FILE that applies, creates or
# replaces from a URL, with kubectl or through the kube helper of
# local-env.sh.
url_applies() {
  local file="$1" number text
  while IFS=$'\t' read -r number text; do
    if [[ $text =~ (^|[^A-Za-z0-9_-])(kubectl|kube)\ .*(apply|create|replace) ]] &&
      [[ $text =~ [A-Za-z][A-Za-z0-9+.-]*:// ]]; then
      printf '%s:%s: applied from a URL: %s\n' "$file" "$number" "$text"
    fi
  done < <(logical_lines "$file")
}

samples="$(mktemp -d)" || exit 2
trap 'rm -rf "${samples:?}"' EXIT
printf '%s\n' \
  'kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.7.0/standard-install.yaml' \
  'kube apply --server-side \' \
  '  -f https://example.invalid/crds.yaml' \
  'kube apply -k github.com/org/repo//dir?ref=v1 --filename=http://example.invalid/x' \
  'kubectl create -f oci://example.invalid/x' >"$samples/bad.sh"
printf '%s\n' \
  'kube apply --server-side -f "$vendor/gateway-api/standard-install.yaml"' \
  '# kubectl apply -f https://example.invalid/x, in a comment' \
  'die "the CRDs come from https://github.com, never applied from there"' \
  'kube apply -k k8s/overlays/local' >"$samples/good.sh"
bad_found="$(url_applies "$samples/bad.sh" | wc -l | tr -d ' ')"
if [ "$bad_found" != 4 ]; then
  echo "the URL rule caught $bad_found of the 4 bad samples:" >&2
  url_applies "$samples/bad.sh" >&2
  exit 1
fi
good_found="$(url_applies "$samples/good.sh")"
if [ -n "$good_found" ]; then
  echo "the URL rule refused good samples:" >&2
  printf '%s\n' "$good_found" >&2
  exit 1
fi
problems=""
while IFS= read -r file; do
  problems="$problems$(url_applies "$file")"
done < <(command_files)
[ -z "$problems" ] || fail "$problems"

# --- The sums are checked before kubectl is called ---------------------------------

if [ ! -f "$platform_script" ]; then
  fail "$platform_script is missing: it checks the sums, then applies the platform (spec 001, T061)."
  exit 1
fi
controller_image="$(awk '$1 == "ENVOY_GATEWAY_IMAGE:" { print $2; exit }' local/tasks/local.yml)"
if [ -z "$controller_image" ]; then
  fail "local/tasks/local.yml has no ENVOY_GATEWAY_IMAGE: platform.sh needs the controller image (T061)."
  exit 1
fi

# A copy of what platform.sh reads, and a simulated kubectl ahead of PATH.
copy() {
  rm -rf "${samples:?}/layer"
  mkdir -p "$samples/layer/local"
  cp -R local/scripts local/vendor local/platform "$samples/layer/local/"
  cp platform.yaml "$samples/layer/"
}
mkdir -p "$samples/bin"
ln -s "$root/$fake_kubectl" "$samples/bin/kubectl"
calls="$samples/calls.log"

# run_platform CASE ACTION: runs platform.sh ACTION on the copy, with HOME in
# the sandbox; sets out and status.
run_platform() {
  : >"$calls"
  status=0
  out="$(HOME="$samples" FAKE_LOG="$calls" PATH="$samples/bin:$PATH" \
    bash "$samples/layer/$platform_script" "$2" "$controller_image" 2>&1)" || status=$?
  if [ -s "$calls" ]; then
    fail "case \"$1\": platform.sh $2 called kubectl: $(tr '\n' ';' <"$calls")"
  fi
}

expect_refused() {
  if [ "$status" -eq 0 ]; then
    fail "case \"$1\": platform.sh $2 passed; a refusal was expected."
  fi
  case "$out" in
    *"$3"*) ;;
    *) fail "case \"$1\": the refusal of platform.sh $2 does not name $3: $out" ;;
  esac
}

copy
run_platform "intact copy" check
[ "$status" -eq 0 ] || fail "case \"intact copy\": platform.sh check refused: $out"

target="envoy-gateway/gateway-helm.yaml"
for action in check up; do
  copy
  printf ' ' >>"$samples/layer/$vendor/$target"
  run_platform "one byte added" "$action"
  expect_refused "one byte added" "$action" "$target"

  copy
  printf 'kind: Namespace\n' >"$samples/layer/$vendor/extra.yaml"
  run_platform "unlisted file" "$action"
  expect_refused "unlisted file" "$action" "extra.yaml"

  copy
  rm -f "$samples/layer/$vendor/$target"
  run_platform "listed file gone" "$action"
  expect_refused "listed file gone" "$action" "$target"
done

if [ "$failures" -gt 0 ]; then
  exit 1
fi
echo "Every vendored file has its SHA-256, checked by platform.sh before kubectl; nothing is applied from a URL."
