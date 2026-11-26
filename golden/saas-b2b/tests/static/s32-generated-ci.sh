#!/usr/bin/env bash
# control: S32
# carries: FR-011, FR-013; constitution, principles I, VII and VIII; tasks.md, gaps 26 and 40
#
# The CI of the generated project runs what the project promises, and needs
# nothing outside the project to do it (spec 001, tasks.md, gaps 26 and 40).
# In golden/saas-b2b/.github/workflows/:
# - job check installs kubectl from tests/tools/install.sh, checked against its
#   SHA-256, instead of the one of the runner image (gap 40);
# - job unit runs `task test`;
# - job e2e-lite runs `task test:e2e` with PROFILE=lite, in 45 minutes at most
#   like the job of CELIAN, with kind and kubectl from tests/tools/install.sh
#   (gap 26);
# - job scan-images runs the scan of the pulled images (E27);
# - each of these jobs checks out with persist-credentials: false and sets no
#   permissions of its own, so that it keeps the contents: read of the
#   workflow;
# - no workflow calls scripts/ci/ or catalog/, which exist in CELIAN only.
# The versions have one source each: kind in local/scripts/lib/preflight-checks.sh,
# kubectl in tests/tools/install.sh, whose minor is the one of platform.yaml, and
# both sums in tests/tools/SHA256SUMS. Actions pinned by SHA and the absence of
# plan, apply and cloud credential are S17; Renovate comments are S23.
# These workflows do not run in CELIAN: this control reads them, and X01 runs
# actionlint on them in a copy.
#
# Usage: s32-generated-ci.sh                    the whole control
#        s32-generated-ci.sh --workflow <file>...  the rules on these workflows only
#        s32-generated-ci.sh --kind-sum <catalog> <sums>  the two sums of kind only
# The two options serve the failing cases of tests/static/s32-cases/: each
# case must fail, and its output must hold the text of its "# expect:" line.
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
CDPATH='' cd -- "$root"

self="${BASH_SOURCE[0]}"
workflows_dir=".github/workflows"
install_script="tests/tools/install.sh"
sums_file="tests/tools/SHA256SUMS"
preflight="local/scripts/lib/preflight-checks.sh"
cases_dir="tests/static/s32-cases"
celian_catalog="$root/../../catalog/kubernetes-cluster.yaml"

problems=0

report() {
  problems=$((problems + 1))
  printf '%s\n' "$1"
}

mode="all"
case "${1:-}" in
  --workflow)
    mode="workflow"
    shift
    ;;
  --kind-sum)
    mode="kind-sum"
    shift
    ;;
esac

workflow_files=()
if [ "$mode" = workflow ]; then
  workflow_files=("$@")
else
  for file in "$workflows_dir"/*.yml "$workflows_dir"/*.yaml; do
    if [ -f "$file" ]; then
      workflow_files+=("$file")
    fi
  done
fi

# Prints the block of job $2 of workflow $1: from its "  <job>:" line, at two
# spaces of indent, to the next job or the end of the file. Nothing if absent.
job_block() {
  awk -v job="$2" '
    $0 == "  " job ":" { inside = 1; print; next }
    inside && /^  [A-Za-z0-9_-]+:/ { inside = 0 }
    inside && /^[^ #]/ { inside = 0 }
    inside { print }
  ' "$1"
}

# The workflow that holds job $1, or nothing.
file_of_job() {
  local file
  for file in ${workflow_files[@]+"${workflow_files[@]}"}; do
    if [ -n "$(job_block "$file" "$1")" ]; then
      printf '%s\n' "$file"
      return 0
    fi
  done
  return 0
}

# Prints the code lines of stdin, comments removed.
code_only() {
  sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#.*$//' | grep -v '^[[:space:]]*$' || true
}

# True when the workflow $1 grants contents: read, and nothing else, at the top.
top_permissions_ok() {
  awk '
    /^permissions:[[:space:]]*$/ { inside = 1; next }
    inside && /^[^ #]/ { inside = 0 }
    inside && /^[[:space:]]+[a-z-]+:/ {
      count++
      if ($0 ~ /^[[:space:]]+contents:[[:space:]]*read[[:space:]]*$/) { ok = 1 }
    }
    END { exit (ok && count == 1) ? 0 : 1 }
  ' "$1"
}

# The rules that every job of this control shares: it exists, its checkout
# keeps no credential, it sets no permissions of its own, and its workflow
# grants contents: read at the top. The commands of each job come after.
check_shared() {
  local job="$1" file block
  file="$(file_of_job "$job")"
  if [ -z "$file" ]; then
    report "job $job: not found in $workflows_dir/. The generated project must run it (gaps 26 and 40)."
    return 0
  fi
  block="$(job_block "$file" "$job" | code_only)"
  if ! printf '%s\n' "$block" | grep -q -E '^[[:space:]]+persist-credentials:[[:space:]]*false[[:space:]]*$'; then
    report "$file, job $job: no persist-credentials: false on its checkout."
  fi
  if printf '%s\n' "$block" | grep -q -E '^[[:space:]]+permissions:'; then
    report "$file, job $job: sets permissions of its own; it keeps the contents: read of the workflow."
  fi
  # A job that cannot fail the run, or that a condition can switch off, checks
  # nothing: the four jobs run on every pull request and fail it when they fail.
  # continue-on-error is refused on the job and on its steps; the job-level
  # if: is the four-space key of the job.
  if printf '%s\n' "$block" | grep -q -E '^[[:space:]]*(-[[:space:]]+)?continue-on-error:'; then
    report "$file, job $job: sets continue-on-error; the job must be able to fail the run."
  fi
  if printf '%s\n' "$block" | grep -q -E '^    if:'; then
    report "$file, job $job: has a job-level if; the job runs on every pull request and push."
  fi
  if ! top_permissions_ok "$file"; then
    report "$file: the workflow must grant contents: read at the top, and nothing else."
  fi
}

# True when job $2 of file $1 has a code line that matches the regex $3.
job_has() {
  job_block "$1" "$2" | code_only | grep -q -E -e "$3"
}

require_line() {
  local job="$1" regex="$2" message="$3" file
  file="$(file_of_job "$job")"
  [ -n "$file" ] || return 0
  if ! job_has "$file" "$job" "$regex"; then
    report "$file, job $job: $message"
  fi
}

installs_with() {
  # The install step names the tools after the directory: kind kubectl.
  local job="$1" tool="$2"
  require_line "$job" "tests/tools/install\\.sh .*(^|[[:space:]])${tool}([[:space:]]|\$)" \
    "does not install $tool with tests/tools/install.sh (SHA-256 checked, one source for the versions)."
}

check_workflows() {
  local job file
  for job in check unit e2e-lite scan-images; do
    check_shared "$job"
  done

  # Gap 40: task check renders with the kubectl of the project, not the runner's.
  installs_with check kubectl

  # Unit tests.
  require_line unit '^[[:space:]]+run:[[:space:]]*task test[[:space:]]*$' "does not run 'task test'."

  # End-to-end tests on kind, lite profile (gap 26).
  installs_with e2e-lite kind
  installs_with e2e-lite kubectl
  require_line e2e-lite '^[[:space:]]+PROFILE:[[:space:]]*lite[[:space:]]*$' "does not set PROFILE: lite."
  require_line e2e-lite '^[[:space:]]+run:[[:space:]]*task test:e2e[[:space:]]*$' "does not run 'task test:e2e'."
  require_line e2e-lite '^[[:space:]]+timeout-minutes:[[:space:]]*45[[:space:]]*$' \
    "has no 'timeout-minutes: 45', the delay of the job of CELIAN."

  # Scan of the pulled images.
  require_line scan-images 'tests/scan/e27-pulled-images\.sh' "does not run tests/scan/e27-pulled-images.sh (E27)."
  installs_with scan-images trivy

  # The project stands alone: nothing that only CELIAN has.
  for file in ${workflow_files[@]+"${workflow_files[@]}"}; do
    if code_only <"$file" | grep -q -E 'scripts/ci/|catalog/'; then
      report "$file: calls scripts/ci/ or catalog/, which exist in CELIAN only; a generated project stands alone."
    fi
  done
}

# True when "<sum>  <key>" is in the sums file $2.
sum_line() {
  awk -v key="$1" '$2 == key && $1 ~ /^[0-9a-f]{64}$/ { found = 1 } END { exit found ? 0 : 1 }' "$2"
}

# One source for the versions, and the sums that go with them.
check_versions() {
  local kind_version kubectl_version minor
  kind_version="$(awk -F'"' '/^KIND_VERSION=/ { print $2; exit }' "$preflight" 2>/dev/null || true)"
  kubectl_version="$(awk -F'"' '/^KUBECTL_VERSION=/ { print $2; exit }' "$install_script" 2>/dev/null || true)"
  minor="$(awk -F'"' '/^kubernetes_minor:/ { print $2; exit }' platform.yaml 2>/dev/null || true)"

  if [ -z "$kind_version" ]; then
    report "$preflight: no KIND_VERSION line; it is the one source of the version of kind."
  fi
  if [ -n "$(awk '/^KIND_VERSION=/ { print "x" }' "$install_script")" ]; then
    report "$install_script: sets its own KIND_VERSION; it must read the one of $preflight."
  fi
  if [ -z "$kubectl_version" ]; then
    report "$install_script: no KUBECTL_VERSION line, so kubectl has no pinned version."
  elif [ -n "$minor" ] && [ "${kubectl_version%.*}" != "$minor" ]; then
    report "$install_script: KUBECTL_VERSION $kubectl_version is not on the Kubernetes minor $minor of platform.yaml."
  fi

  # The Linux amd64 guard of kind and kubectl comes before mkdir -p "$dest":
  # on another system, the call fails and leaves no directory behind.
  if ! awk '
    /Linux amd64 only/ && !guard { guard = NR }
    /^mkdir -p "\$dest"/ && !make { make = NR }
    END { exit (guard && make && guard < make) ? 0 : 1 }
  ' "$install_script"; then
    report "$install_script: the Linux amd64 guard of kind and kubectl must come before mkdir -p \"\$dest\"."
  fi

  if [ -n "$kind_version" ] && ! sum_line "kubernetes-sigs/kind/v$kind_version/kind-linux-amd64" "$sums_file"; then
    report "$sums_file: no SHA-256 for kubernetes-sigs/kind/v$kind_version/kind-linux-amd64."
  fi
  if [ -n "$kubectl_version" ] && ! sum_line "kubernetes/kubernetes/v$kubectl_version/kubectl-linux-amd64" "$sums_file"; then
    report "$sums_file: no SHA-256 for kubernetes/kubernetes/v$kubectl_version/kubectl-linux-amd64."
  fi
}

# The sum of kind exists twice: in the catalog of CELIAN (catalog/
# kubernetes-cluster.yaml, local target, platform linux-amd64) and in $2, the
# SHA256SUMS that install.sh checks the binary against. Both come from the
# release of kind; they must be the same, for the same version.
check_kind_sum() {
  local catalog="$1" sums="$2" version catalog_sum file_sum key
  version="$(awk -F'"' '/^[[:space:]]+version:/ { print $2; exit }' "$catalog" 2>/dev/null || true)"
  catalog_sum="$(awk '
    /platform:[[:space:]]*linux-amd64/ { want = 1; next }
    /platform:/ { want = 0 }
    want && /sha256:/ { v = $0; sub(/.*sha256:[[:space:]]*/, "", v); gsub(/["[:space:]]/, "", v); print v; exit }
  ' "$catalog" 2>/dev/null || true)"
  if [ -z "$version" ] || [ -z "$catalog_sum" ]; then
    report "$catalog: no version or no linux-amd64 sha256 for kind."
    return 0
  fi
  key="kubernetes-sigs/kind/v$version/kind-linux-amd64"
  file_sum="$(awk -v key="$key" '$2 == key { print $1; exit }' "$sums" 2>/dev/null || true)"
  if [ -z "$file_sum" ]; then
    report "$sums: no SHA-256 for $key, the version of kind in the catalog."
  elif [ "$file_sum" != "$catalog_sum" ]; then
    report "$sums: the SHA-256 of $key differs from the one in the catalog ($catalog)."
  fi
}

# Each failing case of tests/static/s32-cases/ is run through this script
# alone: it must fail, and its output must hold the text of its "# expect:"
# line. A *.yml file is a workflow; kind-sum/ holds the two copies of the sum
# of kind, catalog.yaml and SHA256SUMS.
check_cases() {
  local case_file expect out found=0
  for case_file in "$cases_dir"/*.yml "$cases_dir"/kind-sum/catalog.yaml; do
    [ -f "$case_file" ] || continue
    found=$((found + 1))
    expect="$(awk -v key='# expect: ' 'NR > 10 { exit } index($0, key) == 1 { print substr($0, length(key) + 1); exit }' "$case_file")"
    if [ -z "$expect" ]; then
      report "$case_file: no '# expect:' line"
      continue
    fi
    case "$case_file" in
      */kind-sum/catalog.yaml) out="$(bash "$self" --kind-sum "$case_file" "$(dirname -- "$case_file")/SHA256SUMS" 2>&1)" && out="" || true ;;
      *) out="$(bash "$self" --workflow "$case_file" 2>&1)" && out="" || true ;;
    esac
    if [ -z "$out" ]; then
      report "$case_file: accepted, yet it is a failing case: $expect"
    elif ! printf '%s\n' "$out" | grep -F -q -e "$expect"; then
      report "$case_file: refused, but no message holds: $expect"
    fi
  done
  if [ "$found" -eq 0 ]; then
    report "$cases_dir holds no failing case."
  fi
}

case "$mode" in
  workflow)
    check_workflows
    ;;
  kind-sum)
    if [ "$#" -ne 2 ]; then
      report "usage: s32-generated-ci.sh --kind-sum <catalog> <sums>"
    else
      check_kind_sum "$1" "$2"
    fi
    ;;
  all)
    check_workflows
    check_versions
    # The catalog is CELIAN's: a project rendered alone has no copy to compare.
    if [ -f "$celian_catalog" ] && [ "$(CDPATH='' cd -- "$root/../.." && pwd)/golden/saas-b2b" = "$root" ]; then
      check_kind_sum "$celian_catalog" "$sums_file"
    fi
    check_cases
    ;;
esac

if [ "$problems" -gt 0 ]; then
  exit 1
fi
