#!/usr/bin/env bash
# Scans the images of the inventory of a profile for one platform, keeps the
# SBOM of the images that the project builds, then decides with the policy of
# the repository (spec 001, FR-020 to FR-022; research RS-22 to RS-24):
# - the inventory comes from local/scripts/image-inventory.sh. The pulled
#   images (node, mirror, Envoy Gateway, Postgres, cache) are read from their
#   registry, for the platform of the run. The images under saas-b2b.invalid,
#   the API and the front, are built here, the way task up builds them: the
#   Dockerfile, the build context and the stage come from local/scripts/app.sh
#   (API_CONTEXT, API_DOCKERFILE, FRONT_CONTEXT, FRONT_DOCKERFILE,
#   IMAGE_STAGE), and the build runs for the platform of the run. Trivy reads
#   the built image from the engine of the machine, under the tag
#   saas-b2b.invalid/<name>:scan, which the script removes at the end;
# - Trivy, installed and checked by tests/tools/install.sh, writes one JSON
#   report per image, every severity kept. It runs under env -i, with its
#   cache and its HOME in a directory of this run, removed at the end: the
#   vulnerability database is downloaded in each run, from its default
#   repositories, and kept nowhere. The options are those of research RS-22;
#   S26 reads them through a fake trivy. It gets DOCKER_HOST besides PATH and
#   HOME for a built image, the one of the caller or else the address of the
#   docker context, because under env -i it would not find the engine;
# - for each built image, a second Trivy call writes the SBOM, CycloneDX in
#   JSON, to <sbom-dir>/<name>-<arch>.cdx.json. With --format cyclonedx Trivy
#   disables the security scan and needs no database: the SBOM lists
#   components and versions, and nothing else (FR-020). The CI keeps that
#   directory as an artifact of the run;
# - the front compiles react and react-dom into dist/, so neither its SBOM nor
#   the scan of its image lists them. The scan also runs trivy fs on its
#   package-lock.json, with the same options, writes the report as one more
#   report of the policy (named saas-b2b.invalid/front/package-lock.json, the
#   class blocking) and an SBOM to <sbom-dir>/front-lock-<arch>.cdx.json
#   (decision of the DSI, 2026-11-26);
# - conftest runs policy/scan_decision.rego on the reports, the two
#   exception files, the policy of security/scan-policy.yaml, the date of
#   the day in UTC and the platform of the run. It refuses each image and
#   vulnerability at or above the threshold without a valid exception, naming
#   both, on the images that go to production or that no class holds
#   (blocking and unclassified, decision of the DSI of 2026-11-25), and every
#   report of such an image that is empty or of another platform. The reported
#   images, third-party images of the local cluster, do not block: a table of
#   them (image, CRITICAL, HIGH, distinct identifiers, with a fix) goes to the
#   output and to $GITHUB_STEP_SUMMARY when it is set, as does a table of the
#   blocking images, built ones included.
# Fails when Trivy fails, saying so when the database could not be
# downloaded or an image has no variant for the platform (spec 001, edge
# case): the scan never passes without a database fetched in this run, and
# never on a report of another variant. The pulled images come first, so that
# a missing database stops the run before any build.
#
# Usage: tests/scan/scan-images.sh [--db-repository <repository>]
#          [--platform linux/amd64|linux/arm64] --sbom-dir <directory> lite
# --platform is the variant that this run is for, linux/amd64 by default. The
# CI scans each of the two in a job of its own, the arm64 one on an arm64
# runner, so that every build is native. --db-repository serves the E27 case
# only, and is refused outside a host under .invalid, which resolves to no
# registry (research RS-07; S26).
# Needs the network (the database, each pulled image, the base images of the
# builds) and an engine that runs docker.
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
CDPATH='' cd -- "$root"

policy_file="security/scan-policy.yaml"
exception_files="security/scan-exceptions.yaml local/security/scan-exceptions.yaml"
app_script="local/scripts/app.sh"
# The images that the project builds sit under this host (research RS-07), and
# the scan builds them under a tag of its own.
built_host="saas-b2b.invalid"
scan_tag="scan"
# Trivy stops at 5m0s by default (research RS-22); the node image is the
# heaviest of the inventory.
trivy_timeout="10m"
pass_line="no blocking image carries a vulnerability at or above the threshold without a valid exception"

usage="usage: tests/scan/scan-images.sh [--db-repository <repository under .invalid>] [--platform linux/amd64|linux/arm64] --sbom-dir <directory> lite"

fail() {
  printf 'E27: %s\n' "$1" >&2
  exit 1
}

db_repository=""
platform="linux/amd64"
sbom_dir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --db-repository)
      [ "$#" -ge 2 ] || fail "$usage"
      db_repository="$2"
      shift 2
      ;;
    --platform)
      [ "$#" -ge 2 ] || fail "$usage"
      platform="$2"
      shift 2
      ;;
    --sbom-dir)
      [ "$#" -ge 2 ] || fail "$usage"
      sbom_dir="$2"
      shift 2
      ;;
    -*) fail "$usage" ;;
    *) break ;;
  esac
done
[ "$#" -eq 1 ] || fail "$usage"
profile="$1"

case "$platform" in
  linux/amd64 | linux/arm64) ;;
  *) fail "$platform is not a platform of the scan: linux/amd64 or linux/arm64, the two variants that a Mac and a runner build and run (decision of the DSI, 2026-11-26)." ;;
esac
arch="${platform#linux/}"
[ -n "$sbom_dir" ] || fail "--sbom-dir is required: the SBOM of each built image is written there, and the CI keeps it as an artifact of the run (FR-020)."

if [ -n "$db_repository" ]; then
  case "${db_repository%%/*}" in
    *.invalid) ;;
    *)
      printf 'S26: %s: the vulnerability database comes from the default repositories of Trivy only; --db-repository serves the E27 case, under a host in .invalid (research RS-22).\n' "$db_repository" >&2
      exit 1
      ;;
  esac
fi

for tool in trivy conftest docker; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    fail "$tool is not installed: run tests/tools/install.sh <dir> for Trivy and conftest, then put <dir> on PATH; docker builds the images of the project."
  fi
done
# shellcheck disable=SC2086 # $exception_files is a list of paths without spaces
for file in "$policy_file" "$app_script" $exception_files; do
  [ -f "$file" ] || fail "$file is missing: the scan reads its threshold, its exceptions and the build of its images there."
done

refs="$(bash local/scripts/image-inventory.sh "$profile")" || fail "the inventory of the $profile profile fails (message above)."

work="$(mktemp -d)"
built_tags=""
# Removes the tags that this run made, and nothing else, then the directory of
# the run. A tag already gone is not an error.
cleanup() {
  local tag
  for tag in $built_tags; do
    docker rmi "$tag" >/dev/null 2>&1 || true
  done
  rm -rf "${work:?}"
}
trap cleanup EXIT
mkdir -p "$work/home" "$work/reports" "$sbom_dir"

# The address of the engine that holds the built images: DOCKER_HOST of the
# caller, else the one of the current docker context.
engine_host=""
find_engine() {
  if [ -n "${DOCKER_HOST:-}" ]; then
    engine_host="$DOCKER_HOST"
    return 0
  fi
  engine_host="$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null)" || engine_host=""
  [ -n "$engine_host" ] || fail "no docker engine: docker context inspect gives no address, and DOCKER_HOST is not set. The built images are read from the engine."
}

# Trivy on image $1, its JSON report written to $2, read from the registry
# ($3 = remote) or from the engine of the machine ($3 = docker); research
# RS-22.
run_trivy() {
  local ref="$1" output="$2" source="$3"
  set -- image --quiet --config '' --cache-dir "$work/cache" \
    --disable-telemetry --skip-version-check --ignorefile '' \
    --scanners vuln --offline-scan \
    --timeout "$trivy_timeout" --exit-code 0 --format json --output "$output"
  if [ "$source" = remote ]; then
    set -- "$@" --image-src remote --platform "$platform"
  else
    set -- "$@" --image-src docker
  fi
  if [ -n "$db_repository" ]; then
    set -- "$@" --db-repository "$db_repository"
  fi
  if [ "$source" = remote ]; then
    env -i PATH="$PATH" HOME="$work/home" trivy "$@" "$ref"
  else
    env -i PATH="$PATH" HOME="$work/home" DOCKER_HOST="$engine_host" trivy "$@" "$ref"
  fi
}

# The SBOM of built image $1, CycloneDX JSON, written to $2. No --scanners:
# the SBOM lists components and versions, not vulnerabilities, and needs no
# database.
run_sbom() {
  local ref="$1" output="$2"
  env -i PATH="$PATH" HOME="$work/home" DOCKER_HOST="$engine_host" trivy image --quiet --config '' \
    --cache-dir "$work/cache" --disable-telemetry --skip-version-check --ignorefile '' \
    --timeout "$trivy_timeout" --image-src docker --format cyclonedx --output "$output" "$ref"
}

# The value of the constant $1 that app.sh writes as: readonly NAME="value".
app_constant() {
  awk -v key="$1" '
    $1 == "readonly" {
      pair = $2
      name = pair
      sub(/=.*$/, "", name)
      if (name != key) next
      value = pair
      sub(/^[^=]*=/, "", value)
      gsub(/["\047]/, "", value)
      print value
      exit
    }
  ' "$app_script"
}

# Builds the image $1 (api, front) the way task up does, for the platform of
# the run, under the tag of the scan; sets built_ref. A build that fails
# prints its own messages, and stops the scan here.
build_image() {
  local name="$1" key context dockerfile stage
  key="$(printf '%s' "$name" | tr 'a-z-' 'A-Z_')"
  context="$(app_constant "${key}_CONTEXT")"
  dockerfile="$(app_constant "${key}_DOCKERFILE")"
  stage="$(app_constant IMAGE_STAGE)"
  [ -n "$context" ] && [ -n "$dockerfile" ] && [ -n "$stage" ] ||
    fail "$app_script names no ${key}_CONTEXT, ${key}_DOCKERFILE or IMAGE_STAGE: the scan builds $built_host/$name the way task up does (FR-020)."
  built_ref="$built_host/$name:$scan_tag"
  printf 'E27: building %s for %s\n' "$built_ref" "$platform"
  built_tags="$built_tags $built_ref"
  docker build --quiet --platform "$platform" --target "$stage" --tag "$built_ref" \
    --file "$root/$context/$dockerfile" "$root/$context" >/dev/null ||
    fail "the image $built_host/$name was not built; the messages of docker are above."
}

# Scans the lock file $1 of the built image $2 with trivy fs, same policy and
# same options as the images (research RS-22), and writes its SBOM. The front
# compiles react and react-dom into dist/, so neither its SBOM nor its scan of
# the image sees them: the lock file is the one place that lists them. The
# file is copied under <built host>/<name>/ and read by that relative path, so
# that Trivy names the artifact by it and the policy holds the class blocking
# and the exceptions for it, like for an image. Sets n to the report number.
scan_lock() {
  local file="$1" name="$2" base rel sbom
  [ -f "$file" ] || fail "$file is missing: the scan reads the packages that $built_host/$name compiles into its files there (FR-020, FR-021)."
  base="$(basename "$file")"
  rel="$built_host/$name/$base"
  mkdir -p "$work/lock/$built_host/$name"
  cp "$file" "$work/lock/$rel"
  n=$((n + 1))
  printf 'E27: scanning %s\n' "$rel"
  set -- fs --quiet --config '' --cache-dir "$work/cache" \
    --disable-telemetry --skip-version-check --ignorefile '' \
    --timeout "$trivy_timeout"
  if [ -n "$db_repository" ]; then
    set -- "$@" --db-repository "$db_repository"
  fi
  (
    CDPATH='' cd -- "$work/lock"
    env -i PATH="$PATH" HOME="$work/home" trivy "$@" \
      --scanners vuln --offline-scan --exit-code 0 --format json --output "$work/reports/$n.json" "$rel"
  ) 2>"$work/trivy.err" || trivy_failed "$rel"
  sbom="$sbom_dir/$name-lock-$arch.cdx.json"
  (
    CDPATH='' cd -- "$work/lock"
    env -i PATH="$PATH" HOME="$work/home" trivy fs --quiet --config '' \
      --cache-dir "$work/cache" --disable-telemetry --skip-version-check --ignorefile '' \
      --timeout "$trivy_timeout" --format cyclonedx --output "$sbom" "$rel"
  ) 2>"$work/trivy.err" || trivy_failed "$rel"
  if [ ! -s "$sbom" ] || ! grep -q -F '"bomFormat": "CycloneDX"' "$sbom" || ! grep -q -F '"components"' "$sbom"; then
    fail "the SBOM of $rel is empty or is not CycloneDX JSON with components: $sbom (FR-020)."
  fi
  printf 'E27: SBOM of %s: %s, %s bytes\n' "$rel" "$sbom" "$(wc -c <"$sbom" | tr -d ' ')"
}

# Says why Trivy failed on $1, from its messages in $work/trivy.err, and stops.
trivy_failed() {
  local ref="$1"
  cat "$work/trivy.err" >&2
  if grep -q 'failed to download vulnerability DB' "$work/trivy.err"; then
    fail "the vulnerability database could not be downloaded${db_repository:+ from $db_repository}: the scan fails, and never passes without a database fetched in this run (spec 001, edge case; research RS-22)."
  fi
  if grep -q 'no child with platform' "$work/trivy.err"; then
    fail "$ref has no variant for $platform: its index lists none, so the scan has nothing to read for that platform (decision of the DSI, 2026-11-26)."
  fi
  fail "Trivy could not scan $ref for $platform (message above)."
}

pulled=0
built=0
built_refs=""
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  case "$ref" in
    "$built_host"/*)
      built_refs="$built_refs $ref"
      continue
      ;;
  esac
  pulled=$((pulled + 1))
  printf 'E27: scanning %s for %s\n' "$ref" "$platform"
  run_trivy "$ref" "$work/reports/$pulled.json" remote 2>"$work/trivy.err" || trivy_failed "$ref"
done < <(printf '%s\n' "$refs")

[ "$pulled" -gt 0 ] || fail "the inventory of the $profile profile holds no pulled image."
[ -n "$built_refs" ] ||
  fail "the inventory of the $profile profile holds no built image: the API and the front are built under $built_host, and the scan builds them, keeps their SBOM and reads them (FR-020, FR-021)."

find_engine
n="$pulled"
for ref in $built_refs; do
  name="${ref#"$built_host"/}"
  name="${name%%[:@]*}"
  build_image "$name"
  n=$((n + 1))
  built=$((built + 1))
  printf 'E27: scanning %s for %s\n' "$built_ref" "$platform"
  run_trivy "$built_ref" "$work/reports/$n.json" docker 2>"$work/trivy.err" || trivy_failed "$built_host/$name"
  sbom="$sbom_dir/$name-$arch.cdx.json"
  run_sbom "$built_ref" "$sbom" 2>"$work/trivy.err" || trivy_failed "$built_host/$name"
  if [ ! -s "$sbom" ] || ! grep -q -F '"bomFormat": "CycloneDX"' "$sbom" || ! grep -q -F '"components"' "$sbom"; then
    fail "the SBOM of $built_host/$name is empty or is not CycloneDX JSON with components: $sbom (FR-020)."
  fi
  printf 'E27: SBOM of %s for %s: %s, %s bytes\n' "$built_host/$name" "$platform" "$sbom" "$(wc -c <"$sbom" | tr -d ' ')"
  if [ "$name" = front ]; then
    front_context="$(app_constant FRONT_CONTEXT)"
    scan_lock "$front_context/package-lock.json" front
  fi
done

printf '{"scan_today": "%s", "scan_platform": "%s"}\n' "$(date -u +%Y-%m-%d)" "$platform" >"$work/run.json"
decision=0
# shellcheck disable=SC2086 # $exception_files is a list of paths without spaces
conftest test --no-color --combine --policy policy --namespace scan_decision \
  --data "$policy_file" --data "$work/run.json" "$work"/reports/*.json $exception_files >"$work/decision.txt" 2>&1 || decision=$?
cat "$work/decision.txt"

# The reported images, third-party images of the local cluster that do not
# block (decision of the DSI, 2026-11-25): one row each, from the "reported:"
# lines of the decision, in the output and in the summary of the job.
awk '
  BEGIN {
    print "| Image | CRITICAL | HIGH | Distinct identifiers | With a fix |"
    print "| --- | --- | --- | --- | --- |"
  }
  # Anchored on the start of a WARN line: the deny lines carry package names
  # that come from the reports.
  /^WARN - .* reported: [^ ]+: [0-9]+ CRITICAL, / {
    line = $0
    sub(/^WARN - .* reported: /, "", line)
    image = line
    sub(/: [0-9]+ CRITICAL, .*$/, "", image)
    rest = line
    sub(/^[^ ]+: /, "", rest)
    split(rest, p, /[ ,;]+/)
    # p: 1 and 3 count CRITICAL and HIGH, 5 the distinct identifiers, 11 those with a fix
    print "| " image " | " p[1] " | " p[3] " | " p[5] " | " p[11] " |"
  }
' "$work/decision.txt" >"$work/table.md"
# The images that block, built ones included: one row each, from the count
# lines of the decision, with how many findings are refused.
awk -v platform="$platform" '
  BEGIN {
    print "| Image | Platform | CRITICAL | HIGH | MEDIUM | LOW | UNKNOWN | Refused |"
    print "| --- | --- | --- | --- | --- | --- | --- | --- |"
  }
  /^WARN - [^ ]+ - [^ ]+ - [^ ]+: [0-9]+ CRITICAL, [0-9]+ HIGH, [0-9]+ MEDIUM, [0-9]+ LOW, [0-9]+ UNKNOWN; [0-9]+ at or above / {
    line = $0
    sub(/^WARN - [^ ]+ - [^ ]+ - /, "", line)
    image = line
    sub(/: [0-9]+ CRITICAL, .*$/, "", image)
    rest = line
    sub(/^[^ ]+: /, "", rest)
    split(rest, p, /[ ,;]+/)
    # p: 1, 3, 5, 7 and 9 count CRITICAL, HIGH, MEDIUM, LOW and UNKNOWN, 11 the refused
    print "| " image " | " platform " | " p[1] " | " p[3] " | " p[5] " | " p[7] " | " p[9] " | " p[11] " |"
  }
' "$work/decision.txt" >"$work/blocking.md"
printf '\nE27: blocking images for %s (a finding at or above the threshold without a valid exception fails the scan):\n' "$platform"
cat "$work/blocking.md"
printf '\nE27: reported images for %s (not blocking; [SECU] reads them at the monthly review of the advisories):\n' "$platform"
cat "$work/table.md"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    printf '### Image scan, %s: blocking images\n\n' "$platform"
    printf 'The images that the project builds, and every image that no class holds. A finding at or above the threshold without a valid exception fails the scan.\n\n'
    cat "$work/blocking.md"
    printf '\n### Image scan, %s: reported images\n\n' "$platform"
    printf 'Third-party images that run on the local cluster only. Their findings at or above the threshold do not block; [SECU] reads this table.\n\n'
    cat "$work/table.md"
    printf '\n'
  } >>"$GITHUB_STEP_SUMMARY"
fi

if [ "$decision" -ne 0 ]; then
  fail "the scan refuses the images above: each vulnerability at or above the threshold of $policy_file, on an image that goes to production or that no class holds, needs a fix or a valid exception written by [SECU] (FR-022); a report that is empty or of another platform is refused too."
fi
printf 'E27: %s pulled and %s built images scanned for %s; %s.\n' "$pulled" "$built" "$platform" "$pass_line"
