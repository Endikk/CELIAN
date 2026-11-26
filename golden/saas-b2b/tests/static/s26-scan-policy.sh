#!/usr/bin/env bash
# control: S26
# carries: FR-021, FR-022; research RS-22, RS-23; CVE-2026-33634, CVE-2026-55092
#
# The policy of the image scan:
# - the threshold is written once, in security/scan-policy.yaml, and read
#   by the decision policy only (policy/scan_decision.rego, through
#   data.scan_policy): Trivy filters nothing (research RS-22). RS-23 keeps
#   HIGH or lower;
# - Trivy comes from its release, checked against tests/tools/SHA256SUMS,
#   at 0.71.1 or later (CVE-2026-55092), never through the actions of Aqua
#   Security (CVE-2026-33634);
# - no option skips the vulnerability database, swaps its source or hides
#   the findings without a fix; the database comes from the default
#   repositories, except for the E27 case under .invalid;
# - no cache of the database from one run to the next;
# - the class of each image (decision of the DSI, 2026-11-25, FR-021 and
#   FR-022): security/scan-policy.yaml holds the classes blocking and
#   reported and no other, each entry a repository in full, no image in both,
#   and no reported image deployed on the gcp target (the render of
#   gcp/k8s/<composition>/ names it): a third-party image of the local
#   cluster that reached production would block nothing. The scan, run
#   against a fake trivy, passes and writes its summary when only reported
#   images carry findings, and fails on an image that no class holds;
# - when the golden repo sits in CELIAN, the CI jobs of the scan are among
#   the required checks of the ruleset of main.
# The scan script runs against a fake trivy (tests/static/fakes/trivy), so
# that what it passes to Trivy is read, not guessed, and nothing goes out.
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
CDPATH='' cd -- "$root"

self="tests/static/s26-scan-policy.sh"
policy_file="security/scan-policy.yaml"
scan="tests/scan/scan-images.sh"
e27="tests/scan/e27-pulled-images.sh"
inventory="local/scripts/image-inventory.sh"
classes="tests/scan/image-classes.sh"
trivy_floor="0.71.1"
pass_line="no pulled blocking image carries a vulnerability at or above the threshold without a valid exception; the images built by task up (saas-b2b.invalid) are scanned from the second PR of step 18"
problems=0

report() {
  problems=$((problems + 1))
  printf '%s\n' "$1"
}

# "<line>:<text>" for each line of $1, comments removed: a comment may name
# a refused option to say why it is absent.
code_lines() {
  sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#.*$//' "$1" | grep -n -v '^[[:space:]]*$' || true
}

for file in "$policy_file" "$scan" "$e27" "$inventory" "$classes" policy/scan_decision.rego tests/tools/install.sh tests/tools/SHA256SUMS; do
  if [ ! -f "$file" ]; then
    echo "$file is missing (spec 001, T115 to T117)." >&2
    exit 1
  fi
done
if ! command -v conftest >/dev/null 2>&1; then
  echo "conftest is not installed: run tests/tools/install.sh <dir>, then put <dir> on PATH." >&2
  exit 1
fi

# 1. The threshold, written once.
count="$(grep -c -E '^[[:space:]]*severity_threshold:' "$policy_file" || true)"
value="$(awk '/^[[:space:]]*severity_threshold:/ { v = $2; gsub(/["'\'']/, "", v); print v; exit }' "$policy_file")"
if [ "$count" != 1 ]; then
  report "$policy_file: $count severity_threshold lines, exactly one expected."
fi
case "$value" in
  LOW | MEDIUM | HIGH) ;;
  CRITICAL) report "$policy_file: threshold CRITICAL; research RS-23 keeps HIGH or lower, so that a HIGH finding cannot pass in silence." ;;
  *) report "$policy_file: threshold \"$value\" is none of LOW, MEDIUM, HIGH." ;;
esac
while IFS= read -r file; do
  case "$file" in
    "./$policy_file" | ./tests/scan-reports/* | ./policy/*_test.rego | "./$self") continue ;;
  esac
  if code_lines "$file" | grep -q -E 'severity_threshold["'\'']?[[:space:]]*:[[:space:]]*["'\'']?(UNKNOWN|LOW|MEDIUM|HIGH|CRITICAL)'; then
    report "$file: writes a severity threshold; it is written once, in $policy_file."
  fi
done < <(find . \( -name .git -o -name node_modules -o -path ./local/vendor \) -prune -o -type f \
  \( -name '*.yaml' -o -name '*.yml' -o -name '*.json' -o -name '*.sh' -o -name '*.rego' \) -print | LC_ALL=C sort)
if ! grep -q -F 'data.scan_policy.severity_threshold' policy/scan_decision.rego; then
  report "policy/scan_decision.rego does not read data.scan_policy.severity_threshold: the decision must take the threshold of $policy_file."
fi

# 2. Trivy from its release, checked, at the floor or later.
trivy_version="$(awk -F '"' '/^TRIVY_VERSION=/ { print $2; exit }' tests/tools/install.sh)"
if [ -z "$trivy_version" ]; then
  report "tests/tools/install.sh: no TRIVY_VERSION=\"x.y.z\" line."
else
  lowest="$(printf '%s\n%s\n' "$trivy_floor" "$trivy_version" | LC_ALL=C sort -t . -k 1,1n -k 2,2n -k 3,3n | head -n 1)"
  if [ "$lowest" != "$trivy_floor" ]; then
    report "tests/tools/install.sh: Trivy $trivy_version is older than $trivy_floor, which fixes CVE-2026-55092."
  fi
  for asset in Linux-64bit Linux-ARM64 macOS-64bit macOS-ARM64; do
    key="aquasecurity/trivy/v$trivy_version/trivy_${trivy_version}_$asset.tar.gz"
    if ! grep -q -E "^[0-9a-f]{64}  $key\$" tests/tools/SHA256SUMS; then
      report "tests/tools/SHA256SUMS: no SHA-256 for $key."
    fi
  done
  # The text of install.sh, read and never expanded.
  # shellcheck disable=SC2016
  if ! grep -q -F 'aquasecurity/trivy/v$TRIVY_VERSION/' tests/tools/install.sh; then
    report "tests/tools/install.sh does not install Trivy from its release, checked against SHA256SUMS."
  fi
fi

# The workflows of the golden repo, and those of CELIAN when the golden repo
# sits there (a standalone copy, X01, has none).
workflows=()
for file in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -f "$file" ] && workflows+=("$file")
done
celian_root="$(CDPATH='' cd -- "$root/../.." && pwd)"
in_celian=0
if [ "$celian_root/golden/saas-b2b" = "$root" ] && [ -f "$celian_root/.github/workflows/golden-saas-b2b.yml" ]; then
  in_celian=1
  for file in "$celian_root"/.github/workflows/*.yml "$celian_root"/.github/workflows/*.yaml; do
    [ -f "$file" ] && workflows+=("$file")
  done
fi

# 3. No action of Aqua Security, no cache of the database.
for file in "${workflows[@]}"; do
  while IFS= read -r entry; do
    report "$file:${entry%%:*}: action of Aqua Security; Trivy comes from its release, checked by tests/tools/install.sh (CVE-2026-33634)."
  done < <(code_lines "$file" | grep -i -E 'aquasecurity/(trivy-action|setup-trivy)' || true)
  while IFS= read -r entry; do
    report "$file:${entry%%:*}: cache of Trivy; the database is downloaded in each run (research RS-22)."
  done < <(code_lines "$file" | grep -i -E 'TRIVY_CACHE_DIR|cache.*trivy|trivy.*cache' || true)
done

# 4. No option that skips, swaps or narrows the database or the findings.
scanned=("${workflows[@]}")
while IFS= read -r file; do
  scanned+=("$file")
done < <(find . \( -name .git -o -name node_modules -o -path ./local/vendor \) -prune -o -type f \
  \( -name '*.sh' -o -path './tests/static/fakes/*' -o -name 'Taskfile.yml' -o -path './local/tasks/*.yml' -o -path './gcp/tasks/*.yml' \) -print | LC_ALL=C sort)
refused='--skip-db-update|--skip-java-db-update|--ignore-unfixed|--java-db-repository|--severity|TRIVY_SKIP_DB_UPDATE|TRIVY_SKIP_JAVA_DB_UPDATE|TRIVY_IGNORE_UNFIXED|TRIVY_DB_REPOSITORY|TRIVY_JAVA_DB_REPOSITORY|TRIVY_SEVERITY'
for file in "${scanned[@]}"; do
  case "$file" in
    "./$self") continue ;;
  esac
  while IFS= read -r entry; do
    report "$file:${entry%%:*}: refused option of the scan: ${entry#*:}"
  done < <(code_lines "$file" | grep -E -e "$refused" || true)
  case "$file" in
    "./$scan" | "./$e27") ;;
    *)
      while IFS= read -r entry; do
        report "$file:${entry%%:*}: --db-repository outside $scan and $e27: the database comes from the default repositories (research RS-22)."
      done < <(code_lines "$file" | grep -E -e '--db-repository' || true)
      ;;
  esac
done

# 5. What the scan passes to Trivy, read through the fake.
work="$(mktemp -d)"
trap 'rm -rf "${work:?}"' EXIT
mkdir -p "$work/bin"
cp tests/static/fakes/trivy "$work/bin/trivy"
chmod 0755 "$work/bin/trivy"
log="$work/bin/trivy.log"

# run_scan MODE ARGS...: runs the scan with the fake in MODE; sets status
# and out.
run_scan() {
  printf '%s\n' "$1" >"$work/bin/mode"
  shift
  : >"$log"
  status=0
  out="$(GITHUB_STEP_SUMMARY="$work/summary.md" PATH="$work/bin:$PATH" bash "$scan" "$@" 2>&1)" || status=$?
}

pulled="$(bash "$inventory" lite | grep -c -v '^saas-b2b\.invalid/' || true)"
run_scan ok lite
if [ "$status" -ne 0 ]; then
  report "$scan lite fails with a fake trivy that finds nothing (status $status):"
  printf '%s\n' "$out"
fi
calls="$(grep -c '^ARGS ' "$log" || true)"
if [ "$calls" != "$pulled" ]; then
  report "$scan called Trivy $calls times for $pulled pulled images of the lite inventory."
fi
while IFS= read -r line; do
  args="|${line#ARGS }|"
  for needed in '|image|' '|--config||' '|--ignorefile||' '|--disable-telemetry|' '|--skip-version-check|' \
    '|--offline-scan|' '|--scanners|vuln|' '|--image-src|remote|' '|--exit-code|0|' '|--format|json|' '|--cache-dir|'; do
    case "$args" in
      *"$needed"*) ;;
      *) report "$scan does not pass $needed to Trivy (arguments joined by |): ${line#ARGS }" ;;
    esac
  done
  case "$args" in
    *'|--db-repository|'* | *'|--server|'* | *'|--severity|'*) report "$scan passes a refused option to Trivy: ${line#ARGS }" ;;
  esac
  cache="${args#*|--cache-dir|}"
  cache="${cache%%|*}"
  case "$cache" in
    "$root"/* | "$HOME"/* | "") report "$scan keeps the cache of Trivy in \"$cache\", not in a directory of the run." ;;
  esac
  if [ -n "$cache" ] && [ -e "$cache" ]; then
    report "$scan leaves the cache of Trivy behind it: $cache"
  fi
done < <(grep '^ARGS ' "$log" || true)
while IFS= read -r line; do
  name="${line#ENV }"
  name="${name%%=*}"
  case "$name" in
    PATH | HOME | PWD | SHLVL | _) ;;
    *) report "$scan runs Trivy with $name in its environment; it runs under env -i, with PATH and HOME only." ;;
  esac
done < <(grep '^ENV ' "$log" | LC_ALL=C sort -u || true)

run_scan ok --db-repository ghcr.io/aquasecurity/trivy-db:2 lite
if [ "$status" -eq 0 ] || grep -q '^ARGS ' "$log" || ! printf '%s\n' "$out" | grep -q 'S26'; then
  report "$scan accepts a database repository outside .invalid, or runs Trivy before refusing it, or does not name S26:"
  printf '%s\n' "$out"
fi

run_scan ok --db-repository registry.invalid.example.com/trivy-db:2 lite
if [ "$status" -eq 0 ] || grep -q '^ARGS ' "$log"; then
  report "$scan accepts a database repository whose host does not end in .invalid."
fi

run_scan ok --db-repository registry.invalid/aquasec/trivy-db:2 lite
if ! grep -q -F '|--db-repository|registry.invalid/aquasec/trivy-db:2|' "$log"; then
  report "$scan does not pass the E27 repository under .invalid to Trivy."
fi

run_scan dbfail lite
if [ "$status" -eq 0 ] || printf '%s\n' "$out" | grep -q -F "$pass_line" ||
  ! printf '%s\n' "$out" | grep -q 'vulnerability database could not be downloaded'; then
  report "$scan does not fail, saying so, when the vulnerability database cannot be downloaded (E27; spec, edge case):"
  printf '%s\n' "$out"
fi

# 6. The jobs of the scan are required checks of main.
if [ "$in_celian" -eq 1 ]; then
  ruleset="$celian_root/.github/rulesets/main.json"
  names="$(awk '
    /^jobs:/ { in_jobs = 1; next }
    in_jobs && /^  [A-Za-z0-9_-]+:[ \t]*$/ { job = $1; sub(/:$/, "", job); name[job] = job; next }
    in_jobs && job != "" && /^    name:[ \t]*/ { n = $0; sub(/^    name:[ \t]*/, "", n); gsub(/["'\'']/, "", n); name[job] = n; next }
    in_jobs && job != "" && $0 !~ /^[ \t]*#/ && /tests\/scan\// { scan[job] = 1 }
    END { for (j in scan) print name[j] }
  ' "$celian_root/.github/workflows/golden-saas-b2b.yml")"
  if [ -z "$names" ]; then
    report "$celian_root/.github/workflows/golden-saas-b2b.yml: no job runs the scan of tests/scan/ (T117)."
  fi
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if ! grep -q -F "\"context\": \"$name\"" "$ruleset"; then
      report "$ruleset: the job $name of the scan is not a required check of main (FR-022)."
    fi
  done < <(printf '%s\n' "$names")
fi

# 7. The classes of the images (decision of the DSI, 2026-11-25).
# class_problems DIR prints one line per problem of the classes written in
# DIR/security/scan-policy.yaml, given the images that the gcp renders of DIR
# deploy (DIR/local/scripts/image-inventory.sh gcp). It prints nothing when
# the classes hold.
class_problems() {
  local dir="$1" listing line class entry other repo ref last
  local blocking_entries="" reported_entries="" known=""
  if ! listing="$(bash "$root/$classes" "$dir/$policy_file" 2>&1)"; then
    printf '%s: %s\n' "$policy_file" "$listing"
    return 0
  fi
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    class="${line%%|*}"
    entry="${line#*|}"
    case "$class" in
      blocking | reported) ;;
      *)
        printf '%s: class "%s" is neither blocking nor reported; the scan knows no other class.\n' "$policy_file" "$class"
        continue
        ;;
    esac
    case " $known " in
      *" $class "*) ;;
      *) known="$known $class" ;;
    esac
    [ -n "$entry" ] || continue
    if [ "$class" = reported ]; then
      if ! printf '%s\n' "$entry" | grep -q -E '^[a-z0-9.-]+(:[0-9]+)?(/[a-z0-9._-]+){2,}$'; then
        printf '%s: reported entry "%s" is not a repository written in full (registry, namespace, name; no tag, no digest, no wildcard).\n' "$policy_file" "$entry"
        continue
      fi
      if printf '%s\n' "$reported_entries" | grep -F -x -q -e "$entry"; then
        printf '%s: reported entry %s is written twice.\n' "$policy_file" "$entry"
      fi
      reported_entries="$reported_entries
$entry"
    else
      if ! printf '%s\n' "$entry" | grep -q -E '^[a-z0-9.-]+(:[0-9]+)?(/[a-z0-9._-]+)*$'; then
        printf '%s: blocking entry "%s" is not a registry or a repository without tag, digest or wildcard.\n' "$policy_file" "$entry"
        continue
      fi
      if printf '%s\n' "$blocking_entries" | grep -F -x -q -e "$entry"; then
        printf '%s: blocking entry %s is written twice.\n' "$policy_file" "$entry"
      fi
      blocking_entries="$blocking_entries
$entry"
    fi
  done < <(printf '%s\n' "$listing")
  for class in blocking reported; do
    case " $known " in
      *" $class "*) ;;
      *) printf '%s: no class %s under image_classes; both classes are written, even empty (an unclassified image blocks, but the list says what is meant).\n' "$policy_file" "$class" ;;
    esac
  done
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    while IFS= read -r other; do
      [ -n "$other" ] || continue
      case "$entry" in
        "$other" | "$other"/*)
          printf '%s: %s is reported and also blocking (through %s); an image holds one class.\n' "$policy_file" "$entry" "$other"
          ;;
      esac
    done < <(printf '%s\n' "$blocking_entries")
  done < <(printf '%s\n' "$reported_entries")
  if [ -f "$dir/$inventory" ]; then
    local gcp_refs
    gcp_refs="$(CDPATH='' cd -- "$dir" && bash "$inventory" gcp 2>&1)" || {
      printf '%s: the inventory of the gcp layer cannot be read, so no reported image is checked against it: %s\n' "$policy_file" "$gcp_refs"
      return 0
    }
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      repo="${ref%%@*}"
      last="${repo##*/}"
      repo="${repo%/*}/${last%%:*}"
      while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        if [ "$repo" = "$entry" ]; then
          printf '%s: %s is a reported image, which runs on the local cluster only, and the render of the gcp layer deploys it (%s): it would go to production without blocking the scan.\n' "$policy_file" "$entry" "$ref"
        fi
      done < <(printf '%s\n' "$reported_entries")
    done < <(printf '%s\n' "$gcp_refs")
  fi
}

while IFS= read -r line; do
  [ -n "$line" ] || continue
  report "$line"
done < <(class_problems "$root")

# make_class_fixture DIR REPORTED_ENTRY GCP_IMAGE [CLASS_LINES...]: a tree
# with a policy of classes, the inventory script and a render of gcp/k8s/prod
# that deploys GCP_IMAGE. Without CLASS_LINES, the classes are blocking
# saas-b2b.invalid and reported REPORTED_ENTRY.
make_class_fixture() {
  local dir="$1" reported="$2" image="$3"
  shift 3
  mkdir -p "$dir/security" "$dir/local/scripts" "$dir/gcp/k8s/prod" "$dir/gcp/k8s/component"
  cp "$inventory" "$dir/$inventory"
  {
    printf '%s\n' 'scan_policy:' '  severity_threshold: HIGH' '  max_exception_days: 90' '  image_classes:'
    if [ "$#" -gt 0 ]; then
      printf '%s\n' "$@"
    else
      printf '%s\n' '    blocking:' '      - saas-b2b.invalid' '    reported:' "      - $reported"
    fi
  } >"$dir/$policy_file"
  printf '%s\n' 'apiVersion: kustomize.config.k8s.io/v1beta1' 'kind: Kustomization' 'resources:' '  - pod.yaml' \
    >"$dir/gcp/k8s/prod/kustomization.yaml"
  printf '%s\n' 'apiVersion: v1' 'kind: Pod' 'metadata:' '  name: example' 'spec:' '  containers:' \
    '    - name: app' "      image: $image" >"$dir/gcp/k8s/prod/pod.yaml"
  printf '%s\n' 'apiVersion: kustomize.config.k8s.io/v1alpha1' 'kind: Component' \
    >"$dir/gcp/k8s/component/kustomization.yaml"
}

# class_refused NAME FRAGMENT: fixture NAME must raise a problem that holds FRAGMENT.
class_refused() {
  local name="$1" fragment="$2" got
  got="$(class_problems "$work/$name")"
  if [ -z "$got" ]; then
    report "fixture $name: the classes pass, yet they must be refused with: $fragment"
  elif ! printf '%s\n' "$got" | grep -F -q -e "$fragment"; then
    report "fixture $name: refused, but no message holds: $fragment"
    printf '%s\n' "$got"
  fi
}

make_class_fixture "$work/class-ok" docker.io/example/tool europe-docker.pkg.dev/project/repo/api:1
got="$(class_problems "$work/class-ok")"
if [ -n "$got" ]; then
  report "fixture class-ok: the classes are refused, yet they hold:"
  printf '%s\n' "$got"
fi

make_class_fixture "$work/class-in-gcp" docker.io/example/tool example/tool:1
class_refused class-in-gcp "docker.io/example/tool is a reported image"

digest_image="docker.io/example/tool@sha256:$(printf '%064d' 0 | tr 0 a)"
make_class_fixture "$work/class-in-gcp-digest" docker.io/example/tool "$digest_image"
class_refused class-in-gcp-digest "the render of the gcp layer deploys it"

# A render of gcp that fails must fail S26: an inventory that cannot be read
# checks nothing about the reported images.
make_class_fixture "$work/class-render-fails" docker.io/example/tool europe-docker.pkg.dev/project/repo/api:1
rm "$work/class-render-fails/gcp/k8s/prod/pod.yaml"
class_refused class-render-fails "the inventory of the gcp layer cannot be read"

make_class_fixture "$work/class-other" docker.io/example/tool europe-docker.pkg.dev/project/repo/api:1 \
  '    blocking:' '      - saas-b2b.invalid' '    reported:' '      - docker.io/example/tool' '    local:' '      - docker.io/example/other'
class_refused class-other 'class "local" is neither blocking nor reported'

make_class_fixture "$work/class-tag" docker.io/example/tool:1.0 europe-docker.pkg.dev/project/repo/api:1
class_refused class-tag 'reported entry "docker.io/example/tool:1.0" is not a repository written in full'

make_class_fixture "$work/class-short" example/tool europe-docker.pkg.dev/project/repo/api:1
class_refused class-short 'reported entry "example/tool" is not a repository written in full'

make_class_fixture "$work/class-both" docker.io/example/tool europe-docker.pkg.dev/project/repo/api:1 \
  '    blocking:' '      - docker.io/example' '    reported:' '      - docker.io/example/tool'
class_refused class-both "is reported and also blocking"

make_class_fixture "$work/class-twice" docker.io/example/tool europe-docker.pkg.dev/project/repo/api:1 \
  '    blocking:' '      - saas-b2b.invalid' '    reported:' '      - docker.io/example/tool' '      - docker.io/example/tool'
class_refused class-twice "is written twice"

make_class_fixture "$work/class-missing" docker.io/example/tool europe-docker.pkg.dev/project/repo/api:1 \
  '    blocking:' '      - saas-b2b.invalid'
class_refused class-missing "no class reported"

make_class_fixture "$work/class-none" docker.io/example/tool europe-docker.pkg.dev/project/repo/api:1
printf '%s\n' 'scan_policy:' '  severity_threshold: HIGH' >"$work/class-none/$policy_file"
class_refused class-none "image_classes"

# 8. The scan with reported images that carry findings, against the fake in
# its high mode: a copy of the tree whose policy holds every pulled image of
# the inventory as reported must pass, say so, and write the table of the
# summary; with one of them left out of the classes, or made blocking, it
# must fail and name it.
copy_scan_tree() {
  local dir="$1"
  mkdir -p "$dir"
  cp -R k8s policy security tests "$dir/"
  cp -R local "$dir/"
  rm -rf "${dir:?}/local/tests"
}

write_classes() {
  local file="$1"
  shift
  {
    printf '%s\n' 'scan_policy:' '  severity_threshold: HIGH' '  max_exception_days: 90' '  image_classes:'
    printf '%s\n' '    blocking:' '      - saas-b2b.invalid'
    printf '%s\n' '    reported:'
    for repo in "$@"; do
      printf '      - %s\n' "$repo"
    done
  } >"$file"
}

# scan_in DIR: runs the scan of the tree DIR against the fake, in high mode.
scan_in() {
  local dir="$1"
  printf '%s\n' high >"$work/bin/mode"
  : >"$log"
  : >"$work/summary.md"
  status=0
  out="$(CDPATH='' cd -- "$dir" && GITHUB_STEP_SUMMARY="$work/summary.md" PATH="$work/bin:$PATH" bash "$scan" lite 2>&1)" || status=$?
}

repositories=()
while IFS= read -r ref; do
  case "$ref" in
    '' | saas-b2b.invalid/*) continue ;;
  esac
  repo="${ref%%@*}"
  last="${repo##*/}"
  repositories+=("${repo%/*}/${last%%:*}")
done < <(bash "$inventory" lite)

if [ "${#repositories[@]}" -gt 0 ]; then
  copy_scan_tree "$work/scan-reported"
  write_classes "$work/scan-reported/$policy_file" "${repositories[@]}"
  scan_in "$work/scan-reported"
  if [ "$status" -ne 0 ]; then
    report "$scan fails when only reported images carry findings (status $status), yet they do not block:"
    printf '%s\n' "$out"
  fi
  if ! printf '%s\n' "$out" | grep -q -F "$pass_line"; then
    report "$scan does not say that no blocking image carries a vulnerability: $pass_line"
  fi
  for repo in "${repositories[@]}"; do
    if ! grep -F -q -e "| $repo | 1 | 2 | 3 | 2 |" "$work/summary.md"; then
      report "the summary of the scan has no row \"| $repo | 1 | 2 | 3 | 2 |\" (CRITICAL, HIGH, distinct, with a fix):"
      cat "$work/summary.md"
      break
    fi
  done
  if ! grep -q -F '| Image | CRITICAL | HIGH | Distinct identifiers | With a fix |' "$work/summary.md"; then
    report "the summary of the scan has no table header \"| Image | CRITICAL | HIGH | Distinct identifiers | With a fix |\"."
  fi

  copy_scan_tree "$work/scan-unclassified"
  write_classes "$work/scan-unclassified/$policy_file" "${repositories[@]:1}"
  scan_in "$work/scan-unclassified"
  if [ "$status" -eq 0 ] || ! printf '%s\n' "$out" | grep -q -F "${repositories[0]}: CVE-2099-1001 (CRITICAL)" ||
    ! printf '%s\n' "$out" | grep -q -F 'unclassified image, blocking by default'; then
    report "$scan does not fail, naming ${repositories[0]}, when no class holds that image (closed on failure):"
    printf '%s\n' "$out"
  fi

  copy_scan_tree "$work/scan-blocking"
  write_classes "$work/scan-blocking/$policy_file" "${repositories[@]:1}"
  awk -v extra="      - ${repositories[0]}" '{ print } /^      - saas-b2b.invalid$/ { print extra }' \
    "$work/scan-blocking/$policy_file" >"$work/scan-blocking/policy.new"
  mv "$work/scan-blocking/policy.new" "$work/scan-blocking/$policy_file"
  scan_in "$work/scan-blocking"
  if [ "$status" -eq 0 ] || ! printf '%s\n' "$out" | grep -q -F 'class blocking'; then
    report "$scan does not fail on a blocking image that carries findings:"
    printf '%s\n' "$out"
  fi
fi

if [ "$problems" -gt 0 ]; then
  exit 1
fi
echo "The scan reads its threshold once, runs the checked Trivy without cache or other database, classes each image, and blocks the merge on what goes to production."
