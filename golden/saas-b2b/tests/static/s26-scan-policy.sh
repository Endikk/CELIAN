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
# - the images that the project builds (second PR of step 18; FR-020): the
#   scan builds each with the Dockerfile and the stage that local/scripts/
#   app.sh names, for the platform of the run, reads it from the engine for the
#   report and for the CycloneDX SBOM (no --scanners on the SBOM call, which
#   needs no database), keeps the SBOM in the directory of --sbom-dir, removes
#   the tag it made, and fails when the build, the report, the SBOM or the
#   variant of the platform is missing, or when no built image is in the
#   inventory;
# - the lock file of the front (decision of the DSI, 2026-11-26): react and
#   react-dom are compiled into dist/, so neither the SBOM nor the scan of the
#   image sees them. The scan runs trivy fs on package-lock.json, with the
#   options of the images, offline and without configuration, under the class
#   blocking, and keeps its CycloneDX SBOM; a HIGH finding, a report without
#   Results or an empty SBOM fails it;
# - the platform of the run: linux/amd64 or linux/arm64, nothing else, and
#   each of the two is scanned by a job of its own, the arm64 one on an arm64
#   runner that builds natively;
# - when the golden repo sits in CELIAN, the CI jobs of the scan are among
#   the required checks of the ruleset of main, each keeps its SBOM as an
#   artifact of the run, and one of them is the arm64 job.
# The scan script runs against a fake trivy and a fake docker
# (tests/static/fakes/), so that what it passes to them is read, not guessed,
# and nothing goes out or is built.
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
pass_line="no blocking image carries a vulnerability at or above the threshold without a valid exception"
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

# 5. What the scan passes to Trivy and to docker, read through the fakes.
work="$(mktemp -d)"
trap 'rm -rf "${work:?}"' EXIT
mkdir -p "$work/bin"
cp tests/static/fakes/trivy "$work/bin/trivy"
cp tests/static/fakes/docker "$work/bin/docker"
chmod 0755 "$work/bin/trivy" "$work/bin/docker"
log="$work/bin/trivy.log"
docker_log="$work/bin/docker.log"
# The behaviour of fake trivy for the built images and of fake docker; the
# case that changes them sets these, and run_scan puts them back.
built_mode=clean
fs_mode=clean
docker_mode=ok

# run_scan MODE ARGS...: runs the scan with fake trivy in MODE for the pulled
# images, in $built_mode for the built ones, and fake docker in $docker_mode;
# sets status and out. The SBOM directory is $work/sbom.
run_scan() {
  printf '%s\n' "$1" >"$work/bin/mode"
  shift
  printf '%s\n' "$built_mode" >"$work/bin/built-mode"
  printf '%s\n' "$docker_mode" >"$work/bin/docker-mode"
  printf '%s\n' "$fs_mode" >"$work/bin/fs-mode"
  printf 'amd64\n' >"$work/bin/built-platform"
  : >"$log"
  : >"$docker_log"
  rm -rf "${work:?}/sbom"
  status=0
  out="$(GITHUB_STEP_SUMMARY="$work/summary.md" PATH="$work/bin:$PATH" bash "$scan" --sbom-dir "$work/sbom" "$@" 2>&1)" || status=$?
  built_mode=clean
  docker_mode=ok
  fs_mode=clean
}

pulled="$(bash "$inventory" lite | grep -c -v '^saas-b2b\.invalid/' || true)"
built="$(bash "$inventory" lite | grep -c '^saas-b2b\.invalid/' || true)"
if [ "$built" -lt 1 ]; then
  report "the inventory of lite holds no image under saas-b2b.invalid: the API and the front are built by task up, and the scan builds them (FR-020)."
fi
run_scan ok lite
if [ "$status" -ne 0 ]; then
  report "$scan lite fails with a fake trivy that finds nothing (status $status):"
  printf '%s\n' "$out"
fi
calls="$(grep -c '^ARGS ' "$log" || true)"
remote_calls="$(grep -c -F -e '|--image-src|remote|' "$log" || true)"
engine_calls="$(grep -c -F -e '|--image-src|docker|' "$log" || true)"
sbom_calls="$(grep '^ARGS image|' "$log" | grep -c -F -e '|--format|cyclonedx|' || true)"
lock_calls="$(grep -c '^ARGS fs|' "$log" || true)"
lock_sbom_calls="$(grep '^ARGS fs|' "$log" | grep -c -F -e '|--format|cyclonedx|' || true)"
if [ "$remote_calls" != "$pulled" ] || [ "$engine_calls" != "$((built * 2))" ] || [ "$sbom_calls" != "$built" ] ||
  [ "$lock_calls" -lt 2 ] || [ "$lock_sbom_calls" != "$((lock_calls / 2))" ] || [ "$calls" != "$((pulled + built * 2 + lock_calls))" ]; then
  report "$scan called Trivy $calls times ($remote_calls pulled, $engine_calls from the engine, $sbom_calls SBOM, $lock_calls on lock files, $lock_sbom_calls lock SBOM) for $pulled pulled and $built built images of the lite inventory: one report per image, one SBOM per built image, and a report and an SBOM for each lock file (the front: package-lock.json)."
fi
while IFS= read -r line; do
  args="|${line#ARGS }|"
  kind=pulled
  case "$args" in
    '|fs|'*)
      kind=lock
      case "$args" in *'|--format|cyclonedx|'*) kind=locksbom ;; esac
      ;;
    *'|--format|cyclonedx|'*) kind=sbom ;;
    *'|--image-src|docker|'*) kind=built ;;
  esac
  case "$kind" in
    lock | locksbom) first='|fs|' ;;
    *) first='|image|' ;;
  esac
  for needed in "$first" '|--config||' '|--ignorefile||' '|--disable-telemetry|' '|--skip-version-check|' '|--cache-dir|' '|--output|'; do
    case "$args" in
      *"$needed"*) ;;
      *) report "$scan does not pass $needed to Trivy (arguments joined by |): ${line#ARGS }" ;;
    esac
  done
  case "$kind" in
    pulled) wanted_args='|--offline-scan| |--scanners|vuln| |--image-src|remote| |--exit-code|0| |--format|json| |--platform|linux/amd64|' ;;
    built) wanted_args='|--offline-scan| |--scanners|vuln| |--image-src|docker| |--exit-code|0| |--format|json|' ;;
    sbom) wanted_args='|--image-src|docker| |--format|cyclonedx|' ;;
    lock) wanted_args='|--offline-scan| |--scanners|vuln| |--exit-code|0| |--format|json|' ;;
    locksbom) wanted_args='|--format|cyclonedx|' ;;
  esac
  for needed in $wanted_args; do
    case "$args" in
      *"$needed"*) ;;
      *) report "$scan does not pass $needed to Trivy for a $kind call (arguments joined by |): ${line#ARGS }" ;;
    esac
  done
  if [ "$kind" = sbom ] || [ "$kind" = locksbom ]; then
    # With --format cyclonedx, Trivy disables the security scan and needs no
    # database; --scanners would add the vulnerabilities to the SBOM, which
    # lists components and versions (FR-020).
    case "$args" in
      *'|--scanners|'*) report "$scan passes --scanners to the SBOM call: the SBOM lists components and versions, not vulnerabilities (arguments joined by |): ${line#ARGS }" ;;
    esac
  fi
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
    PATH | HOME | DOCKER_HOST | PWD | SHLVL | _) ;;
    *) report "$scan runs Trivy with $name in its environment; it runs under env -i, with PATH, HOME and DOCKER_HOST (the engine that holds the built images) only." ;;
  esac
done < <(grep '^ENV ' "$log" | LC_ALL=C sort -u || true)

# The engine of the built images: Trivy reads them there, and under env -i it
# finds the socket only through DOCKER_HOST, taken from the docker context.
if ! grep -q -x -F 'ENV DOCKER_HOST=unix:///fake/docker.sock' "$log"; then
  report "$scan does not give Trivy the engine of the docker context (DOCKER_HOST=unix:///fake/docker.sock) to read the built images."
fi
run_with_host() {
  printf 'ok\n' >"$work/bin/mode"
  printf 'clean\n' >"$work/bin/built-mode"
  printf 'ok\n' >"$work/bin/docker-mode"
  printf 'clean\n' >"$work/bin/fs-mode"
  printf 'amd64\n' >"$work/bin/built-platform"
  : >"$log"
  : >"$docker_log"
  rm -rf "${work:?}/sbom"
  status=0
  out="$(DOCKER_HOST=unix:///caller/docker.sock GITHUB_STEP_SUMMARY="$work/summary.md" PATH="$work/bin:$PATH" bash "$scan" --sbom-dir "$work/sbom" lite 2>&1)" || status=$?
}
run_with_host
if [ "$status" -ne 0 ] || ! grep -q -x -F 'ENV DOCKER_HOST=unix:///caller/docker.sock' "$log" ||
  grep -q -F 'unix:///fake/docker.sock' "$log"; then
  report "$scan does not give Trivy the DOCKER_HOST of its caller as it is:"
  printf '%s\n' "$out"
fi

# What the scan asks of the engine: the build of each built image, for the
# platform of the run, with the Dockerfile and the stage that app.sh names,
# under a tag of its own; then the removal of that tag, and nothing else.
if [ "$built" -ge 1 ]; then
  run_scan ok lite
  builds="$(grep -c '^ARGS build|' "$docker_log" || true)"
  removals="$(grep -c '^ARGS rmi|' "$docker_log" || true)"
  if [ "$builds" != "$built" ] || [ "$removals" != "$built" ]; then
    report "$scan built $builds images and removed $removals tags for $built built images of the inventory."
  fi
  while IFS= read -r line; do
    args="|${line#ARGS }|"
    case "$args" in
      '|context|inspect|'* | '|build|'* | '|rmi|'*) ;;
      *) report "$scan runs a docker command that S26 does not expect: ${line#ARGS }" ;;
    esac
  done < <(grep '^ARGS ' "$docker_log" || true)
  for pair in 'api|src/Api/Dockerfile' 'front|src/front/Dockerfile'; do
    name="${pair%%|*}"
    file="${pair#*|}"
    if ! grep '^ARGS build|' "$docker_log" | grep -F -e "|--tag|saas-b2b.invalid/$name:scan|" | grep -F -e '|--target|runtime|' |
      grep -F -e '|--platform|linux/amd64|' | grep -q -F -e "/$file|"; then
      report "$scan does not build saas-b2b.invalid/$name:scan from $file, stage runtime, for linux/amd64 (the Dockerfile and the stage of local/scripts/app.sh)."
    fi
    if ! grep -q -x -F "ARGS rmi|saas-b2b.invalid/$name:scan" "$docker_log"; then
      report "$scan does not remove the tag saas-b2b.invalid/$name:scan that it made."
    fi
    if [ ! -s "$work/sbom/$name-amd64.cdx.json" ]; then
      report "$scan keeps no SBOM at $work/sbom/$name-amd64.cdx.json."
    fi
  done
fi

# The platform of the run: the pulled images, the build and the file name of
# the SBOM follow it; a platform that is neither amd64 nor arm64 is refused
# before anything runs.
run_scan ok --platform linux/arm64 lite
if [ "$status" -ne 0 ]; then
  report "$scan --platform linux/arm64 lite fails with a fake trivy that finds nothing (status $status):"
  printf '%s\n' "$out"
fi
if [ "$(grep -c -F -e '|--platform|linux/arm64|' "$log" || true)" != "$pulled" ] || grep -q -F -e '|--platform|linux/amd64|' "$log"; then
  report "$scan --platform linux/arm64 does not scan the $pulled pulled images for linux/arm64 alone."
fi
if [ "$(grep '^ARGS build|' "$docker_log" | grep -c -F -e '|--platform|linux/arm64|' || true)" != "$built" ]; then
  report "$scan --platform linux/arm64 does not build the $built built images for linux/arm64."
fi
for name in api front; do
  if [ ! -s "$work/sbom/$name-arm64.cdx.json" ]; then
    report "$scan --platform linux/arm64 keeps no SBOM at $work/sbom/$name-arm64.cdx.json."
  fi
done

run_scan ok --platform linux/riscv64 lite
if [ "$status" -eq 0 ] || [ -s "$log" ] || [ -s "$docker_log" ] || ! printf '%s\n' "$out" | grep -q -F 'linux/amd64 or linux/arm64'; then
  report "$scan accepts linux/riscv64, or runs something before refusing it, or does not name the two platforms:"
  printf '%s\n' "$out"
fi

# Without a directory for the SBOM, nothing runs: an SBOM that has nowhere to
# go is a build image that FR-020 does not cover.
: >"$log"
: >"$docker_log"
status=0
out="$(PATH="$work/bin:$PATH" bash "$scan" lite 2>&1)" || status=$?
if [ "$status" -eq 0 ] || [ -s "$log" ] || [ -s "$docker_log" ] || ! printf '%s\n' "$out" | grep -q -F -e '--sbom-dir'; then
  report "$scan runs without --sbom-dir, or runs something before refusing it, or does not name the option:"
  printf '%s\n' "$out"
fi

# The failures of the built images: each must stop the scan and say which
# image and which rule.
built_mode=high
run_scan ok lite
if [ "$status" -eq 0 ] || ! printf '%s\n' "$out" | grep -q -F 'saas-b2b.invalid/api: CVE-2099-1001 (HIGH)' ||
  ! printf '%s\n' "$out" | grep -q -F 'class blocking'; then
  report "$scan does not fail, naming the image and the vulnerability, when a built image carries a HIGH finding:"
  printf '%s\n' "$out"
fi

built_mode=empty
run_scan ok lite
if [ "$status" -eq 0 ] || ! printf '%s\n' "$out" | grep -q -F 'saas-b2b.invalid/api' ||
  ! printf '%s\n' "$out" | grep -q -F 'the report holds no Results and no Metadata.OS'; then
  report "$scan does not fail, naming the image, on an empty report of a built image (tasks.md, gap 65):"
  printf '%s\n' "$out"
fi

built_mode=wrong-arch
run_scan ok lite
if [ "$status" -eq 0 ] || ! printf '%s\n' "$out" | grep -q -F 'saas-b2b.invalid/api: scanned for linux/arm64, linux/amd64 expected'; then
  report "$scan does not fail when the report of a built image is that of the other variant (an arm64 report for an amd64 run):"
  printf '%s\n' "$out"
fi

built_mode=sbom-empty
run_scan ok lite
if [ "$status" -eq 0 ] || ! printf '%s\n' "$out" | grep -q -F 'the SBOM of saas-b2b.invalid/api'; then
  report "$scan does not fail, naming the image, when its SBOM is empty (FR-020):"
  printf '%s\n' "$out"
fi

# The lock file of the front (decision of the DSI, 2026-11-26): react and
# react-dom are compiled into dist/, so only trivy fs on package-lock.json
# sees them. A HIGH finding there blocks like one in an image, a report
# without Results fails, and so does an empty SBOM.
fs_mode=high
run_scan ok lite
if [ "$status" -eq 0 ] || ! printf '%s\n' "$out" | grep -q -F 'saas-b2b.invalid/front/package-lock.json: CVE-2099-1001 (HIGH)' ||
  ! printf '%s\n' "$out" | grep -q -F 'class blocking'; then
  report "$scan does not fail, naming the lock file and the vulnerability, when package-lock.json of the front carries a HIGH finding:"
  printf '%s\n' "$out"
fi

fs_mode=empty
run_scan ok lite
if [ "$status" -eq 0 ] || ! printf '%s\n' "$out" | grep -q -F 'the report of the lock file holds no Results'; then
  report "$scan does not fail on a report of the lock file that holds no Results:"
  printf '%s\n' "$out"
fi

fs_mode=sbom-empty
run_scan ok lite
if [ "$status" -eq 0 ] || ! printf '%s\n' "$out" | grep -q -F 'the SBOM of saas-b2b.invalid/front/package-lock.json'; then
  report "$scan does not fail, naming the lock file, when its SBOM is empty (FR-020):"
  printf '%s\n' "$out"
fi
for arch in amd64 arm64; do
  case "$arch" in amd64) run_scan ok lite ;; *) run_scan ok --platform linux/arm64 lite ;; esac
  if [ ! -s "$work/sbom/front-lock-$arch.cdx.json" ]; then
    report "$scan keeps no SBOM of the lock file of the front at $work/sbom/front-lock-$arch.cdx.json."
  fi
done

docker_mode=build-fails
run_scan ok lite
if [ "$status" -eq 0 ] || ! printf '%s\n' "$out" | grep -q -F 'saas-b2b.invalid/api was not built' ||
  grep -q -F -e '|--image-src|docker|' "$log"; then
  report "$scan does not fail, naming the image, when its build fails, or goes on to scan it:"
  printf '%s\n' "$out"
fi

# An image that has no variant for the platform of the run: Trivy fails, and
# the scan says which image and which platform.
run_scan novariant --platform linux/arm64 lite
if [ "$status" -eq 0 ] || ! printf '%s\n' "$out" | grep -q -F 'has no variant for linux/arm64' ||
  printf '%s\n' "$out" | grep -q -F "$pass_line"; then
  report "$scan does not fail, saying that the image has no arm64 variant:"
  printf '%s\n' "$out"
fi
run_scan novariant lite
if [ "$status" -ne 0 ]; then
  report "$scan lite fails on an image that has no arm64 variant, though the run is for amd64:"
  printf '%s\n' "$out"
fi

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
# The pulled images come first: without a database, the scan stops before it
# builds anything.
if grep -q '^ARGS build|' "$docker_log"; then
  report "$scan builds an image before it knows that the vulnerability database is reachable."
fi

# 6. The jobs of the scan are required checks of main.
if [ "$in_celian" -eq 1 ]; then
  ruleset="$celian_root/.github/rulesets/main.json"
  # One line per job that runs the scan: its name, then 1 or 0 for: the SBOM
  # directory is given, an upload-artifact step keeps it, that step fails
  # when it finds no file, the job scans for arm64, its runner is an arm64 one.
  jobs_of_scan="$(awk '
    /^jobs:/ { in_jobs = 1; next }
    in_jobs && /^  [A-Za-z0-9_-]+:[ \t]*$/ { job = $1; sub(/:$/, "", job); name[job] = job; next }
    in_jobs && job != "" && /^    name:[ \t]*/ { n = $0; sub(/^    name:[ \t]*/, "", n); gsub(/["'\'']/, "", n); name[job] = n; next }
    in_jobs && job != "" && $0 !~ /^[ \t]*#/ {
      if (/tests\/scan\//) scan[job] = 1
      if (/--sbom-dir/) sbom[job] = 1
      if (/actions\/upload-artifact@/) upload[job] = 1
      if (/if-no-files-found:[ \t]*error/) strict[job] = 1
      if (/retention-days:[ \t]*90([ \t]|$)/) keep[job] = 1
      if (/--platform linux\/arm64/) arm[job] = 1
      if (/runs-on:.*-arm/) armrunner[job] = 1
    }
    END { for (j in scan) print name[j] "|" (sbom[j] + 0) "|" (upload[j] + 0) "|" (strict[j] + 0) "|" (arm[j] + 0) "|" (armrunner[j] + 0) "|" (keep[j] + 0) }
  ' "$celian_root/.github/workflows/golden-saas-b2b.yml" | LC_ALL=C sort)"
  if [ -z "$jobs_of_scan" ]; then
    report "$celian_root/.github/workflows/golden-saas-b2b.yml: no job runs the scan of tests/scan/ (T117)."
  fi
  arm_jobs=0
  amd_jobs=0
  while IFS='|' read -r name sbom_dir upload strict arm armrunner keep; do
    [ -n "$name" ] || continue
    if ! grep -q -F "\"context\": \"$name\"" "$ruleset"; then
      report "$ruleset: the job $name of the scan is not a required check of main (FR-022)."
    fi
    if [ "$sbom_dir" != 1 ] || [ "$upload" != 1 ] || [ "$strict" != 1 ]; then
      report "the job $name of the scan does not keep its SBOM as an artifact of the run: it passes --sbom-dir to the scan, then an actions/upload-artifact step with if-no-files-found: error keeps that directory (FR-020)."
    fi
    if [ "$keep" != 1 ]; then
      report "the job $name of the scan does not write retention-days: 90 on its upload-artifact step: the SBOM is kept for the time that the repository settings say, and the 90 days of the decision of the DSI (2026-11-26) are the maximum of a public repository."
    fi
    if [ "$arm" = 1 ]; then
      arm_jobs=$((arm_jobs + 1))
      if [ "$armrunner" != 1 ]; then
        report "the job $name scans for linux/arm64 on a runner that is not an arm64 one (ubuntu-24.04-arm): the image would be built under emulation, or not at all."
      fi
    else
      amd_jobs=$((amd_jobs + 1))
    fi
  done < <(printf '%s\n' "$jobs_of_scan")
  if [ -n "$jobs_of_scan" ] && { [ "$arm_jobs" -lt 1 ] || [ "$amd_jobs" -lt 1 ]; }; then
    report "the jobs of the scan cover $amd_jobs amd64 and $arm_jobs arm64 variants: each image is scanned for both, by a job of its own (decision of the DSI, 2026-11-26)."
  fi
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
  # The scan reads the lock file of the front (react and react-dom are compiled
  # into dist/); the Dockerfiles it builds from stay out of the copy.
  mkdir -p "$dir/src/front"
  cp src/front/package-lock.json "$dir/src/front/"
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
  printf '%s\n' clean >"$work/bin/built-mode"
  printf '%s\n' ok >"$work/bin/docker-mode"
  printf '%s\n' clean >"$work/bin/fs-mode"
  printf '%s\n' amd64 >"$work/bin/built-platform"
  : >"$log"
  : >"$docker_log"
  : >"$work/summary.md"
  rm -rf "${work:?}/sbom"
  status=0
  out="$(CDPATH='' cd -- "$dir" && GITHUB_STEP_SUMMARY="$work/summary.md" PATH="$work/bin:$PATH" bash "$scan" --sbom-dir "$work/sbom" lite 2>&1)" || status=$?
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
  # The images that block, built ones included: one row each, with the
  # counts by level and how many are refused, for the platform of the run.
  if ! grep -q -F '| Image | Platform | CRITICAL | HIGH | MEDIUM | LOW | UNKNOWN | Refused |' "$work/summary.md"; then
    report "the summary of the scan has no table of the blocking images, header \"| Image | Platform | CRITICAL | HIGH | MEDIUM | LOW | UNKNOWN | Refused |\":"
    cat "$work/summary.md"
  fi
  while IFS= read -r ref; do
    case "$ref" in
      saas-b2b.invalid/*)
        repo="${ref%%:*}"
        if ! grep -F -q -e "| $repo | linux/amd64 | 0 | 0 | 0 | 0 | 0 | 0 |" "$work/summary.md"; then
          report "the summary of the scan has no row \"| $repo | linux/amd64 | 0 | 0 | 0 | 0 | 0 | 0 |\" for a built image:"
          cat "$work/summary.md"
          break
        fi
        ;;
    esac
  done < <(bash "$inventory" lite)
  for name in api front; do
    if [ ! -s "$work/sbom/$name-amd64.cdx.json" ]; then
      report "the scan of a tree whose reported images carry findings keeps no SBOM of $name."
    fi
  done

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

  # An inventory without any built image: the scan has no SBOM to make and no
  # image of the project to read, which FR-020 does not allow to pass.
  copy_scan_tree "$work/scan-no-built"
  write_classes "$work/scan-no-built/$policy_file" "${repositories[@]}"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf 'printf "%%s\\n" %s\n' "${repositories[0]}@sha256:$(printf '%064d' 0 | tr 0 b)"
  } >"$work/scan-no-built/$inventory"
  scan_in "$work/scan-no-built"
  if [ "$status" -eq 0 ] || ! printf '%s\n' "$out" | grep -q -F 'no built image'; then
    report "$scan passes an inventory that holds no image under saas-b2b.invalid, or does not say so:"
    printf '%s\n' "$out"
  fi
fi

if [ "$problems" -gt 0 ]; then
  exit 1
fi
echo "The scan reads its threshold once, runs the checked Trivy without cache or other database, classes each image, and blocks the merge on what goes to production."
