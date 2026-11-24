#!/usr/bin/env bash
# BENCH-008: origin of the OpenTofu code of the GCP layer of the generated
# project. Options: modules written by hand, Cloud Foundation Fabric, and
# terraform-google-modules. Each option writes the same minimal layer under
# tests/bench/bench-008/<option>/ (VPC, GKE Autopilot, Cloud SQL Postgres,
# Memorystore, Artifact Registry, Secret Manager, CI identity through
# Workload Identity Federation). For each option the script measures:
#   - `tofu init`, cold (empty provider cache, no lock file) then warm (new
#     working directory with the lock file of the cold run, provider cache
#     full): time, peak memory, providers downloaded, module packages and
#     real git clones (GIT_TRACE);
#   - `tofu validate` after each init: time, peak memory, warnings;
#   - the compressed size of the providers (`tofu providers mirror`, for
#     darwin_arm64 and linux_amd64) and the git data of the module packages;
#   - the lines written for the option, and the lines of the modules it loads;
#   - `tofu fmt -check` on the option.
# Then one check: the terraform-google-modules layer with the google provider
# pinned to the version the two other options use.
#
# Usage: tests/bench/bench-008-tofu-modules.sh [TRIAL_DIR]
#   TRIAL_DIR, if given, must be missing or empty (default: a new mktemp -d).
#   Environment:
#     OPTIONS="handwritten fabric cft"  options, measured in this order
#     RUNS=3   cold and warm runs per option
#     PAUSE=5  seconds between two runs
#   Results (TSV) in TRIAL_DIR: versions.tsv, runs.tsv, providers.tsv,
#   modules.tsv, lines.tsv, checks.tsv, summary.tsv; command output in
#   TRIAL_DIR/logs/.
# Needs: bash >= 3.2, OpenTofu at the version pinned below, git, jq, awk,
#   find, and /usr/bin/time (BSD `-l` on macOS, GNU `-f` elsewhere). Network
#   access to the OpenTofu registry and to GitHub.
#
# Safety (principle X of the constitution):
#   - only `tofu version`, `init`, `validate`, `fmt` and `providers` can run:
#     run_tofu refuses any other subcommand. No plan, no apply, no destroy,
#     no gcloud. `tofu init` runs with -backend=false: no state, local or
#     remote, is ever written;
#   - the script refuses to start if a GOOGLE_*, CLOUDSDK_* or GCLOUD_*
#     variable is set, and runs tofu under `env -i` with an empty HOME inside
#     TRIAL_DIR: no credential, no ~/.config/gcloud, no ~/.terraformrc;
#   - configurations are copied into TRIAL_DIR before init, so neither
#     .terraform/ nor .terraform.lock.hcl ever lands in the repository. The
#     script checks it at the end, and checks that no *.tfstate exists. It
#     refuses a TRIAL_DIR inside a Git work tree;
#   - `tofu version` also runs under `env -i`;
#   - Git traces are reduced to the clone commands, with TRIAL_DIR in place
#     of its absolute path. The other logs still hold that path, which names
#     the user: do not version the raw data as they are.
# Nothing is cleaned up at the end: TRIAL_DIR keeps providers, modules and
# logs, several GiB for a full series. Nothing secret is in it.
# Side effects outside TRIAL_DIR: network traffic, and the short-lived files
# tofu and git create in the default temporary directory (TMPDIR is cleared,
# so /tmp), such as the provider plugin sockets.
set -euo pipefail
umask 077

# --- Pinned versions ----------------------------------------------------------

readonly TOFU_VERSION="1.13.9"
readonly PLATFORMS="darwin_arm64 linux_amd64"
# Version the hand-written and Fabric layers pin, used by the pin check.
readonly GOOGLE_PIN="8.12.0"
readonly ALLOWED_SUBCOMMANDS=" version init validate fmt providers "

OPTIONS="${OPTIONS:-handwritten fabric cft}"
RUNS="${RUNS:-3}"
PAUSE="${PAUSE:-5}"
readonly OPTIONS RUNS PAUSE

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
readonly CONFIG_ROOT="$SCRIPT_DIR/bench-008"

TRIAL_DIR=""
LOGS=""
TOFU=""
TIME_STYLE=""
EMPTY_HOME=""

# --- Helpers ------------------------------------------------------------------

log() { printf '[bench-008 %s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die() {
  log "ERROR: $*"
  exit 1
}

# `tofu version` under an empty environment, like run_tofu: no variable of
# the machine reaches tofu, and no update check is made.
tofu_version() {
  env -i "PATH=$PATH" "HOME=/var/empty" "CHECKPOINT_DISABLE=1" "$TOFU" version
}

# True if the directory, or its nearest existing parent, is in a Git work
# tree: lock files, logs and TSV files there could be committed by mistake.
in_git_tree() {
  local dir="$1"
  while [ ! -d "$dir" ]; do dir="$(dirname "$dir")"; done
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# Median of the numbers read on stdin, NA if none.
median() {
  sort -n | awk '{ v[NR] = $1 }
    END {
      if (NR == 0) { print "NA"; exit }
      if (NR % 2) { print v[(NR + 1) / 2] } else { printf "%.2f\n", (v[NR / 2] + v[NR / 2 + 1]) / 2 }
    }'
}

# Non-blank lines that are not comments, in the *.tf files of one directory.
count_lines() {
  local dir="$1" file
  for file in "$dir"/*.tf; do
    [ -f "$file" ] && cat "$file"
  done | awk '
    inblock { if ($0 ~ /\*\//) inblock = 0; next }
    /^[[:space:]]*\/\*/ { if ($0 !~ /\*\//) inblock = 1; next }
    /^[[:space:]]*($|#|\/\/)/ { next }
    { n++ }
    END { print n + 0 }'
}

# Total size in bytes of the files matching a name pattern under a directory.
sum_bytes() {
  local dir="$1" pattern="$2" total=0 size file
  while IFS= read -r file; do
    size="$(wc -c <"$file" | tr -d ' ')"
    total=$((total + size))
  done < <(find "$dir" -type f -name "$pattern")
  printf '%s\n' "$total"
}

# run_tofu LOG WORKDIR CACHE_DIR SUBCOMMAND [ARGS...]
# Runs one allowed tofu subcommand under /usr/bin/time, with an empty
# environment. Prints "rc<TAB>seconds<TAB>peak MiB".
run_tofu() {
  local logfile="$1" workdir="$2" cache="$3" sub="$4"
  shift 4
  case "$ALLOWED_SUBCOMMANDS" in
    *" $sub "*) ;;
    *) die "refused tofu subcommand: $sub" ;;
  esac
  local rc=0
  # No TMPDIR: under a long TRIAL_DIR, the provider's go-plugin socket path
  # would exceed the Unix socket limit and the provider would not start.
  # GIT_TRACE (absolute path) logs every git command, to count real clones.
  local -a envs=(
    "PATH=$PATH" "HOME=$EMPTY_HOME"
    "TF_DATA_DIR=$workdir/.terraform" "TF_PLUGIN_CACHE_DIR=$cache"
    "TF_IN_AUTOMATION=1" "TF_INPUT=0" "CHECKPOINT_DISABLE=1"
    "GIT_TERMINAL_PROMPT=0" "GIT_CONFIG_NOSYSTEM=1" "GIT_TRACE=$logfile.git-trace"
  )
  if [ "$TIME_STYLE" = "bsd" ]; then
    /usr/bin/time -l env -i "${envs[@]}" "$TOFU" -chdir="$workdir" "$sub" "$@" >"$logfile" 2>&1 || rc=$?
    awk -v rc="$rc" '
      / real / { s = $1 }
      /maximum resident set size/ { m = $1 / 1048576 }
      END { printf "%s\t%.2f\t%.1f\n", rc, s, m }' "$logfile"
  else
    /usr/bin/time -f 'bench-008-time %e %M' env -i "${envs[@]}" "$TOFU" -chdir="$workdir" "$sub" "$@" >"$logfile" 2>&1 || rc=$?
    awk -v rc="$rc" '
      /^bench-008-time / { s = $2; m = $3 / 1024 }
      END { printf "%s\t%.2f\t%.1f\n", rc, s, m }' "$logfile"
  fi
}

# --- Start-up checks ----------------------------------------------------------

check_environment() {
  local leaked
  leaked="$(env | cut -d= -f1 | grep -E '^(GOOGLE|CLOUDSDK|GCLOUD)_' || true)"
  [ -z "$leaked" ] || die "unset these variables first: $(echo "$leaked" | tr '\n' ' ')"
  TOFU="$(command -v tofu || true)"
  [ -n "$TOFU" ] || die "tofu not found"
  local found
  found="$(tofu_version | awk 'NR == 1 { sub(/^v/, "", $2); print $2 }')"
  [ "$found" = "$TOFU_VERSION" ] || die "OpenTofu $TOFU_VERSION expected, found $found"
  command -v git >/dev/null || die "git not found"
  command -v jq >/dev/null || die "jq not found"
  [ -x /usr/bin/time ] || die "/usr/bin/time not found"
  if [ "$(uname -s)" = "Darwin" ]; then TIME_STYLE="bsd"; else TIME_STYLE="gnu"; fi
  case "$RUNS" in '' | *[!0-9]* | 0) die "RUNS must be a positive integer" ;; esac
  local opt
  for opt in $OPTIONS; do
    [ -d "$CONFIG_ROOT/$opt" ] || die "unknown option: $opt"
    if [ -e "$CONFIG_ROOT/$opt/.terraform" ] || [ -e "$CONFIG_ROOT/$opt/.terraform.lock.hcl" ]; then
      die "$CONFIG_ROOT/$opt already holds .terraform or a lock file"
    fi
  done
}

prepare_trial_dir() {
  if [ "$#" -gt 0 ]; then
    TRIAL_DIR="$1"
    if [ -e "$TRIAL_DIR" ]; then
      [ -d "$TRIAL_DIR" ] || die "$TRIAL_DIR is not a directory"
      [ -z "$(ls -A "$TRIAL_DIR")" ] || die "$TRIAL_DIR is not empty"
    fi
    if in_git_tree "$TRIAL_DIR"; then
      die "$TRIAL_DIR is inside a Git work tree; choose a directory outside any repository"
    fi
    mkdir -p "$TRIAL_DIR"
  else
    TRIAL_DIR="$(mktemp -d)"
    if in_git_tree "$TRIAL_DIR"; then
      rmdir "$TRIAL_DIR"
      die "the temporary directory is inside a Git work tree; pass a TRIAL_DIR outside any repository"
    fi
  fi
  TRIAL_DIR="$(CDPATH='' cd -- "$TRIAL_DIR" && pwd)"
  LOGS="$TRIAL_DIR/logs"
  EMPTY_HOME="$TRIAL_DIR/home"
  mkdir -p "$LOGS" "$EMPTY_HOME"
  log "trial directory: $TRIAL_DIR"
}

record_versions() {
  {
    printf 'item\tvalue\n'
    printf 'date_utc\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'tofu\t%s\n' "$(tofu_version | head -1)"
    printf 'git\t%s\n' "$(git --version)"
    printf 'os\t%s %s\n' "$(uname -s)" "$(uname -r)"
    printf 'arch\t%s\n' "$(uname -m)"
    printf 'time_style\t%s\n' "$TIME_STYLE"
  } >"$TRIAL_DIR/versions.tsv"
}

# --- Measures -----------------------------------------------------------------

new_workdir() {
  local opt="$1" name="$2" dir
  dir="$TRIAL_DIR/$opt/$name"
  mkdir -p "$dir"
  cp "$CONFIG_ROOT/$opt/"*.tf "$dir/"
  printf '%s\n' "$dir"
}

# One init then one validate; appends a line to runs.tsv.
measure_run() {
  local opt="$1" run="$2" kind="$3" work="$4" cache="$5"
  local tag="$opt-run$run-$kind" init validate providers packages clones warnings
  init="$(run_tofu "$LOGS/$tag-init.log" "$work" "$cache" init -input=false -backend=false -no-color)"
  providers="$(grep -c 'Installing .* to the shared cache directory' "$LOGS/$tag-init.log" || true)"
  packages="$(grep -c '^Downloading ' "$LOGS/$tag-init.log" || true)"
  clones=0
  local trace="$LOGS/$tag-init.log.git-trace"
  if [ -f "$trace" ]; then
    clones="$(grep -c 'built-in: git clone' "$trace" || true)"
    # The raw trace holds the user name and the host name of the machine.
    # Keep only the clone commands, with TRIAL_DIR in place of its path.
    grep 'built-in: git clone' "$trace" | awk -v d="$TRIAL_DIR" '{
      while ((i = index($0, d)) > 0) $0 = substr($0, 1, i - 1) "TRIAL_DIR" substr($0, i + length(d))
      print
    }' >"$trace.clones" || true
    rm -f "$trace"
  fi
  validate="$(run_tofu "$LOGS/$tag-validate.log" "$work" "$cache" validate -no-color)"
  warnings="$(grep -c '^Warning:' "$LOGS/$tag-validate.log" || true)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$opt" "$run" "$kind" "$init" \
    "$providers" "$packages" "$clones" "$validate" "$warnings" >>"$TRIAL_DIR/runs.tsv"
  log "$tag: init $(echo "$init" | cut -f2) s (rc $(echo "$init" | cut -f1)), validate $(echo "$validate" | cut -f2) s (rc $(echo "$validate" | cut -f1)), providers downloaded $providers, module packages $packages, git clones $clones"
}

# Facts read once per option, from the first cold working directory.
describe_option() {
  local opt="$1" work="$2" cache="$3" platform zip_bytes mirror
  run_tofu "$LOGS/$opt-providers.log" "$work" "$cache" providers >/dev/null
  run_tofu "$LOGS/$opt-fmt.log" "$work" "$cache" fmt -check -diff >"$LOGS/$opt-fmt.status"
  awk -v o="$opt" '
    /^provider "/ { gsub(/"/, "", $2); p = $2 }
    /^  version *=/ { gsub(/"/, "", $3); printf "%s\t%s\t%s\n", o, p, $3 }' \
    "$work/.terraform.lock.hcl" >>"$TRIAL_DIR/providers.tsv"
  mirror="$TRIAL_DIR/$opt/mirror"
  mkdir -p "$mirror"
  run_tofu "$LOGS/$opt-mirror.log" "$work" "$cache" providers mirror \
    -platform=darwin_arm64 -platform=linux_amd64 "$mirror" >"$LOGS/$opt-mirror.status"
  for platform in $PLATFORMS; do
    zip_bytes="$(sum_bytes "$mirror" "*_${platform}.zip")"
    printf '%s\tproviders_zip_%s\t%s\n' "$opt" "$platform" "$zip_bytes" >>"$TRIAL_DIR/lines.tsv"
  done
  local modules_json="$work/.terraform/modules/modules.json" git_kib=0 git_count=0 kib dir
  if [ -f "$modules_json" ]; then
    jq -r --arg o "$opt" '.Modules[] | select(.Key != "") | [$o, .Key, .Source, (.Version // "")] | @tsv' \
      "$modules_json" >>"$TRIAL_DIR/modules.tsv"
    for dir in "$work/.terraform/modules"/*/.git/objects; do
      [ -d "$dir" ] || continue
      kib="$(du -sk "$dir" | cut -f1)"
      git_kib=$((git_kib + kib))
      git_count=$((git_count + 1))
    done
    local module_lines=0 lines
    while IFS= read -r dir; do
      lines="$(count_lines "$dir")"
      module_lines=$((module_lines + lines))
    done < <(jq -r '[.Modules[] | select(.Key != "")] | unique_by(.Source) | .[].Dir' "$modules_json")
    printf '%s\tmodule_lines_unique\t%s\n' "$opt" "$module_lines" >>"$TRIAL_DIR/lines.tsv"
  fi
  {
    printf '%s\tmodule_git_packages\t%s\n' "$opt" "$git_count"
    printf '%s\tmodule_git_objects_kib\t%s\n' "$opt" "$git_kib"
    printf '%s\tmodules_on_disk_kib\t%s\n' "$opt" "$(du -sk "$work/.terraform/modules" 2>/dev/null | cut -f1 || echo 0)"
    printf '%s\twritten_lines\t%s\n' "$opt" "$(count_lines "$CONFIG_ROOT/$opt")"
  } >>"$TRIAL_DIR/lines.tsv"
}

measure_option() {
  local opt="$1" run cold warm cache
  for run in $(seq 1 "$RUNS"); do
    cache="$TRIAL_DIR/$opt/cache$run"
    mkdir -p "$cache"
    cold="$(new_workdir "$opt" "run$run-cold")"
    measure_run "$opt" "$run" cold "$cold" "$cache"
    if [ "$run" -eq 1 ]; then describe_option "$opt" "$cold" "$cache"; fi
    sleep "$PAUSE"
    # A generated project versions its lock file. Without one, OpenTofu
    # ignores the cache and downloads every provider again.
    warm="$(new_workdir "$opt" "run$run-warm")"
    cp "$cold/.terraform.lock.hcl" "$warm/"
    measure_run "$opt" "$run" warm "$warm" "$cache"
    sleep "$PAUSE"
  done
}

# The terraform-google-modules layer with google pinned like the others.
check_cft_pin() {
  local work result first
  work="$(new_workdir cft pin-check)"
  cat >"$work/pin.tf" <<EOF
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "$GOOGLE_PIN"
    }
  }
}
EOF
  mkdir -p "$TRIAL_DIR/cft/pin-cache"
  result="$(run_tofu "$LOGS/cft-pin-check-init.log" "$work" "$TRIAL_DIR/cft/pin-cache" init -input=false -backend=false -no-color)"
  first="$(grep -m1 -E 'no available releases match|Error:' "$LOGS/cft-pin-check-init.log" || true)"
  printf 'cft_google_pinned_%s\tinit_rc=%s\t%s\n' "$GOOGLE_PIN" "$(echo "$result" | cut -f1)" "$first" >>"$TRIAL_DIR/checks.tsv"
}

# --- Report -------------------------------------------------------------------

column_median() {
  local opt="$1" kind="$2" col="$3"
  awk -F'\t' -v o="$opt" -v k="$kind" -v c="$col" '$1 == o && $3 == k { print $c }' \
    "$TRIAL_DIR/runs.tsv" | median
}

fact() {
  awk -F'\t' -v o="$1" -v k="$2" '$1 == o && $2 == k { print $3 }' "$TRIAL_DIR/lines.tsv"
}

write_summary() {
  local opt
  printf 'option\tinit_cold_s\tinit_warm_s\tvalidate_s\tpeak_mib\tproviders_warm\tpackages_warm\tclones_warm\tzip_darwin_arm64_mb\tzip_linux_amd64_mb\tgit_objects_mb\twritten_lines\tmodule_lines\n' \
    >"$TRIAL_DIR/summary.tsv"
  for opt in $OPTIONS; do
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$opt" \
      "$(column_median "$opt" cold 5)" "$(column_median "$opt" warm 5)" \
      "$(column_median "$opt" cold 11)" \
      "$(awk -F'\t' -v o="$opt" '$1 == o { print $6; print $12 }' "$TRIAL_DIR/runs.tsv" | sort -n | tail -1)" \
      "$(column_median "$opt" warm 7)" "$(column_median "$opt" warm 8)" "$(column_median "$opt" warm 9)" \
      "$(awk -v b="$(fact "$opt" providers_zip_darwin_arm64)" 'BEGIN { printf "%.1f", b / 1000000 }')" \
      "$(awk -v b="$(fact "$opt" providers_zip_linux_amd64)" 'BEGIN { printf "%.1f", b / 1000000 }')" \
      "$(awk -v k="$(fact "$opt" module_git_objects_kib)" 'BEGIN { printf "%.1f", k * 1024 / 1000000 }')" \
      "$(fact "$opt" written_lines)" "$(fact "$opt" module_lines_unique | grep . || echo 0)" >>"$TRIAL_DIR/summary.tsv"
  done
  column -t -s "$(printf '\t')" "$TRIAL_DIR/summary.tsv" >&2 || cat "$TRIAL_DIR/summary.tsv" >&2
}

final_checks() {
  local opt states
  for opt in $OPTIONS; do
    if [ -e "$CONFIG_ROOT/$opt/.terraform" ] || [ -e "$CONFIG_ROOT/$opt/.terraform.lock.hcl" ]; then
      die "$CONFIG_ROOT/$opt received .terraform or a lock file"
    fi
  done
  states="$(find "$TRIAL_DIR" "$CONFIG_ROOT" -name '*.tfstate*' -print)"
  [ -z "$states" ] || die "state files found: $states"
  log "no state file, nothing written in $CONFIG_ROOT"
}

main() {
  check_environment
  prepare_trial_dir "$@"
  record_versions
  printf 'option\trun\tkind\tinit_rc\tinit_s\tinit_peak_mib\tproviders_downloaded\tmodule_packages_downloaded\tgit_clones\tvalidate_rc\tvalidate_s\tvalidate_peak_mib\tvalidate_warnings\n' \
    >"$TRIAL_DIR/runs.tsv"
  printf 'option\tprovider\tversion\n' >"$TRIAL_DIR/providers.tsv"
  printf 'option\tkey\tsource\tversion\n' >"$TRIAL_DIR/modules.tsv"
  printf 'option\tfact\tvalue\n' >"$TRIAL_DIR/lines.tsv"
  printf 'check\tresult\tfirst_error\n' >"$TRIAL_DIR/checks.tsv"
  local opt
  for opt in $OPTIONS; do
    log "option $opt"
    measure_option "$opt"
  done
  case " $OPTIONS " in *" cft "*) check_cft_pin ;; esac
  write_summary
  final_checks
  log "done: $TRIAL_DIR"
}

main "$@"
