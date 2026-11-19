#!/usr/bin/env bash
# BENCH-002: day-2 trial of the template engines (Copier, Cookiecutter alone,
# cruft, Yeoman), plus generation determinism (US-004) and generation cost.
# Also runs the R-22 fallback (template branch, then git merge) for reference.
#
# Each run starts from an empty directory and:
#   1. builds the toy template in version 1 and 2 from tests/bench/bench-002/;
#   2. generates a project from v1, twice, and compares both copies;
#   3. commits a local change in the project (app.conf, pipeline.yml, a new
#      local-notes.txt file);
#   4. updates the project to v2 with each tool, and classifies each file.
#
# v2 changes app.conf far from the local edit (a clean merge is possible),
# pipeline.yml on the very line edited locally (a conflict is expected) and
# NOTICE.txt, which is not touched locally.
#
# Usage: tests/bench/bench-002-day2.sh [TRIAL_DIR]  (default: a new mktemp -d)
#   TRIAL_DIR, if given, must be missing or empty.
#   RUNS=3 by default. OPTIONS="copier cookiecutter cruft yeoman" by default;
#   a subset skips the others (e.g. OPTIONS="copier cruft").
#   Results: TRIAL_DIR/generation.tsv, TRIAL_DIR/day2.tsv, and the resolved
#   dependency versions in TRIAL_DIR/resolved-*.txt.
# Needs: git >= 2.32, uv (uvx), Node.js >= 22.18 with npx.
#
# Side effects outside TRIAL_DIR: the uv and npm download caches. yo also
# depends on configstore and update-notifier, which write under
# XDG_CONFIG_HOME (default ~/.config). The script disables update-notifier
# (NO_UPDATE_NOTIFIER) and points XDG_CONFIG_HOME into TRIAL_DIR. Both
# safeguards, like the npm and uv ones below, were added after the
# 2026-11-19 measures, and the Yeoman path has not been run with them.
set -euo pipefail

readonly COPIER_VERSION="9.19.1"
readonly COOKIECUTTER_VERSION="2.7.1"
readonly CRUFT_VERSION="2.16.0"
readonly YO_VERSION="7.0.1"
# Published on 2026-11-16: with the 7-day npm floor below, npx cannot resolve
# it before 2026-11-23.
readonly YEOMAN_GENERATOR_VERSION="10.3.1"
readonly RUNS="${RUNS:-3}"
readonly PROJECT_NAME="demo"
readonly ALL_OPTIONS="copier cookiecutter cruft yeoman"
OPTIONS="${OPTIONS:-$ALL_OPTIONS}"
readonly OPTIONS

# Python side: fixed interpreter, and nothing uploaded after the measure date
# (UTC timestamp, so the cut-off does not depend on the local time zone).
readonly UV_PYTHON="3.13"
readonly UV_EXCLUDE_NEWER="2026-11-19T00:00:00Z"

# npm side: no install scripts (yo 7.0.1 declares postinstall: yodoctor), and
# no version published less than 7 days ago, transitive ones included.
export npm_config_ignore_scripts=true
export npm_config_min_release_age=7

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
readonly SELF
readonly FIXTURES="$SCRIPT_DIR/bench-002"
TRIAL_DIR=""

# Keep git independent from the user's configuration (signing, hooks, names).
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME="bench" GIT_AUTHOR_EMAIL="bench@example.invalid"
export GIT_COMMITTER_NAME="bench" GIT_COMMITTER_EMAIL="bench@example.invalid"
export NO_UPDATE_NOTIFIER=1

log() { printf '[bench-002] %s\n' "$*" >&2; }

# Portable in-place sed (BSD and GNU sed disagree on -i).
replace_in_file() {
  local expr=$1 file=$2
  sed "$expr" "$file" >"$file.tmp"
  mv "$file.tmp" "$file"
}

commit_all() {
  local dir=$1 message=$2
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "$message"
}

# --- Template fixtures -------------------------------------------------------

build_copier_template() {
  local repo=$1 version
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  for version in 1 2; do
    git -C "$repo" rm -rq --ignore-unmatch . >/dev/null
    cp "$FIXTURES/copier/copier.yml" "$repo/"
    cp "$FIXTURES/copier/answers.jinja" "$repo/{{_copier_conf.answers_file}}.jinja"
    cp "$FIXTURES/content/v$version/"{app.conf,pipeline.yml,NOTICE.txt} "$repo/"
    sed 's/@@PROJECT_NAME@@/{{ project_name }}/' \
      "$FIXTURES/content/v$version/PROJECT.txt" >"$repo/PROJECT.txt.jinja"
    commit_all "$repo" "v$version"
    git -C "$repo" tag "v$version"
  done
}

build_cookiecutter_template() {
  local repo=$1 version project_dir
  project_dir="$repo/{{cookiecutter.project_name}}"
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  for version in 1 2; do
    git -C "$repo" rm -rq --ignore-unmatch . >/dev/null
    mkdir -p "$project_dir"
    cp "$FIXTURES/cookiecutter/cookiecutter.json" "$repo/"
    cp "$FIXTURES/content/v$version/"{app.conf,pipeline.yml,NOTICE.txt} "$project_dir/"
    sed 's/@@PROJECT_NAME@@/{{ cookiecutter.project_name }}/' \
      "$FIXTURES/content/v$version/PROJECT.txt" >"$project_dir/PROJECT.txt"
    commit_all "$repo" "v$version"
    git -C "$repo" tag "v$version"
  done
}

# Yeoman generators are npm packages: one directory per version.
build_yeoman_generator() {
  local dir=$1 version=$2 app
  app="$dir/generators/app"
  mkdir -p "$app/templates"
  sed "s/@@VERSION@@/$version.0.0/" "$FIXTURES/yeoman/package.json.tpl" >"$dir/package.json"
  cp "$FIXTURES/yeoman/index.js" "$app/index.js"
  cp "$FIXTURES/content/v$version/"{app.conf,pipeline.yml,NOTICE.txt} "$app/templates/"
  # The <%= %> tags are EJS, Yeoman's template syntax, not shell.
  # shellcheck disable=SC2016
  sed 's/@@PROJECT_NAME@@/<%= projectName %>/' \
    "$FIXTURES/content/v$version/PROJECT.txt" >"$app/templates/PROJECT.txt"
}

# --- Tool wrappers -----------------------------------------------------------

uv_run() { uvx --python "$UV_PYTHON" --exclude-newer "$UV_EXCLUDE_NEWER" "$@"; }
run_copier() { uv_run "copier@$COPIER_VERSION" "$@"; }
run_cookiecutter() { uv_run "cookiecutter@$COOKIECUTTER_VERSION" "$@"; }
run_cruft() { uv_run "cruft@$CRUFT_VERSION" "$@"; }
run_yo() {
  npx --yes -p "yo@$YO_VERSION" -p "yeoman-generator@$YEOMAN_GENERATOR_VERSION" -- yo "$@"
}

# The generator imports yeoman-generator. npx keeps it in its own cache, so
# the generators' parent directory gets a node_modules link to that cache.
npx_node_modules() {
  local yo_bin
  yo_bin="$(npx --yes -p "yo@$YO_VERSION" -p "yeoman-generator@$YEOMAN_GENERATOR_VERSION" \
    -c 'command -v yo')"
  dirname "$(dirname "$yo_bin")"
}

has_option() {
  case " $OPTIONS " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# Writes the exact versions installed in each tool environment.
record_resolved_versions() {
  local node_modules=$1 spec name
  # Python code run inside the uvx environment, not shell.
  # shellcheck disable=SC2016
  local list_dists='import importlib.metadata as m, platform
print("python==" + platform.python_version())
print("\n".join(sorted(d.name + "==" + d.version for d in m.distributions())))'
  for spec in "copier==$COPIER_VERSION" "cookiecutter==$COOKIECUTTER_VERSION" \
    "cruft==$CRUFT_VERSION"; do
    name="${spec%%==*}"
    has_option "$name" || continue
    uv_run --from "$spec" python -c "$list_dists" >"$TRIAL_DIR/resolved-$name.txt"
    log "$name: $(grep -c '==' "$TRIAL_DIR/resolved-$name.txt") entries in resolved-$name.txt"
  done
  if [[ -n "$node_modules" ]]; then
    if npm ls --all --prefix "$(dirname "$node_modules")" >"$TRIAL_DIR/resolved-yeoman.txt"; then
      log "yeoman: resolved tree in resolved-yeoman.txt"
    else
      log "yeoman: npm ls reported problems, see resolved-yeoman.txt"
    fi
  fi
}

# generate <option> <version> <project_dir> <template>
generate() {
  local option=$1 version=$2 project=$3 tpl=$4
  case "$option" in
    copier)
      run_copier copy --quiet --defaults --data "project_name=$PROJECT_NAME" \
        --vcs-ref "v$version" "$tpl" "$project"
      ;;
    cookiecutter)
      run_cookiecutter --no-input --checkout "v$version" -o "$(dirname "$project")" \
        "git+file://$tpl" "project_name=$PROJECT_NAME"
      ;;
    cruft)
      run_cruft create "$tpl" --checkout "v$version" --no-input \
        --extra-context "{\"project_name\": \"$PROJECT_NAME\"}" \
        --output-dir "$(dirname "$project")"
      ;;
    yeoman)
      mkdir -p "$project"
      (cd "$project" && run_yo "$tpl-v$version/generators/app" --skip-install \
        --projectname="$PROJECT_NAME")
      ;;
  esac
}

# update <variant> <project_dir> <template>. Prints nothing, returns the
# tool's exit code.
update() {
  local variant=$1 project=$2 tpl=$3
  case "$variant" in
    copier)
      (cd "$project" && run_copier update --quiet --defaults --vcs-ref v2 --conflict inline)
      ;;
    cruft)
      run_cruft update --project-dir "$project" --checkout v2 --skip-apply-ask
      ;;
    cookiecutter-no-force)
      run_cookiecutter --no-input --checkout v2 -o "$(dirname "$project")" \
        "git+file://$tpl" "project_name=$PROJECT_NAME"
      ;;
    cookiecutter-force)
      run_cookiecutter --no-input --checkout v2 --overwrite-if-exists \
        -o "$(dirname "$project")" "git+file://$tpl" "project_name=$PROJECT_NAME"
      ;;
    cookiecutter-skip-existing)
      run_cookiecutter --no-input --checkout v2 --overwrite-if-exists --skip-if-file-exists \
        -o "$(dirname "$project")" "git+file://$tpl" "project_name=$PROJECT_NAME"
      ;;
    yeoman-default)
      (cd "$project" && run_yo "$tpl-v2/generators/app" --skip-install </dev/null)
      ;;
    yeoman-force)
      (cd "$project" && run_yo "$tpl-v2/generators/app" --skip-install --force </dev/null)
      ;;
    git-branch-fallback)
      update_git_branch "$project" "$tpl"
      ;;
  esac
}

# R-22 fallback, outside the three options: a "template" branch holds the
# pristine generated output; v2 is regenerated there, then merged into main.
# Cookiecutter generates, git does the three-way merge.
update_git_branch() {
  local project=$1 tpl=$2 regen
  regen="$(dirname "$project")/regen"
  mkdir -p "$regen"
  run_cookiecutter --no-input --checkout v2 -o "$regen" \
    "git+file://$tpl" "project_name=$PROJECT_NAME" &&
    git -C "$project" branch template HEAD~1 &&
    git -C "$project" checkout -q template &&
    git -C "$project" rm -rq . &&
    cp -R "$regen/$PROJECT_NAME/." "$project/" &&
    commit_all "$project" "chore: regenerate from template v2" &&
    git -C "$project" checkout -q main &&
    git -C "$project" merge --no-edit template
}

# --- Measures ----------------------------------------------------------------

# timed <stats_file> <log_file> <command...>: runs the command under
# /usr/bin/time and writes "seconds max_rss_kib" to stats_file. The peak RSS
# is the largest one among the command's processes (uvx or npx included).
timed() {
  local stats=$1 logfile=$2 raw
  shift 2
  raw="$stats.raw"
  case "$(uname -s)" in
    Darwin)
      /usr/bin/time -l -p "$@" >"$logfile" 2>"$raw"
      awk '/^real /{s=$2} /maximum resident set size/{r=int($1/1024)} END{print s, r}' \
        "$raw" >"$stats"
      ;;
    *)
      /usr/bin/time -f 'BENCHTIME %e %M' "$@" >"$logfile" 2>"$raw"
      awk '/^BENCHTIME /{print $2, $3}' "$raw" >"$stats"
      ;;
  esac
}

has_conflict() {
  local file=$1
  [[ -f "$file.rej" ]] || grep -q '^<<<<<<<' "$file" 2>/dev/null
}

classify_app_conf() {
  local file=$1/app.conf kept_local=no applied=no
  if has_conflict "$file"; then echo "conflict-flagged"; return; fi
  grep -q '^port = 9090$' "$file" && kept_local=yes
  grep -q '^log_format = json$' "$file" && applied=yes
  case "$kept_local/$applied" in
    yes/yes) echo "clean-merge" ;;
    no/yes) echo "silent-overwrite" ;;
    yes/no) echo "template-change-dropped" ;;
    *) echo "other" ;;
  esac
}

classify_pipeline() {
  local file=$1/pipeline.yml
  if has_conflict "$file"; then echo "conflict-flagged"
  elif grep -q '^runner: medium$' "$file"; then echo "silent-overwrite"
  elif grep -q '^runner: large$' "$file"; then echo "template-change-dropped"
  else echo "other"
  fi
}

classify_notice() {
  if grep -q '^Template version 2$' "$1/NOTICE.txt"; then echo "applied"; else echo "not-applied"; fi
}

classify_local_notes() {
  if [[ -f "$1/local-notes.txt" ]]; then echo "kept"; else echo "deleted"; fi
}

unmerged_files() {
  local files
  files="$(git -C "$1" diff --name-only --diff-filter=U | tr '\n' ',' | sed 's/,$//')"
  echo "${files:--}"
}

make_local_change() {
  local project=$1
  git -C "$project" init -q -b main
  commit_all "$project" "chore: generate from template v1"
  replace_in_file 's/^port = 8080$/port = 9090/' "$project/app.conf"
  replace_in_file 's/^runner: small$/runner: large/' "$project/pipeline.yml"
  printf 'Team notes, not in the template.\n' >"$project/local-notes.txt"
  commit_all "$project" "chore: local customisation"
}

# --- One run -----------------------------------------------------------------

template_for() {
  local option=$1 tpl_dir=$2
  case "$option" in
    copier) echo "$tpl_dir/copier" ;;
    cookiecutter | cruft) echo "$tpl_dir/cookiecutter" ;;
    yeoman) echo "$tpl_dir/yeoman" ;;
  esac
}

variants_for() {
  case "$1" in
    copier) echo "copier" ;;
    cruft) echo "cruft" ;;
    cookiecutter)
      echo "cookiecutter-no-force cookiecutter-force cookiecutter-skip-existing git-branch-fallback"
      ;;
    yeoman) echo "yeoman-default yeoman-force" ;;
  esac
}

run_once() {
  local run=$1 node_modules=$2 run_dir tpl_dir logs option tpl
  run_dir="$TRIAL_DIR/run-$run"
  rm -rf "${run_dir:?}"
  tpl_dir="$run_dir/templates"
  logs="$run_dir/logs"
  mkdir -p "$tpl_dir" "$logs"

  # Cookiecutter (and cruft) clone into this run's directory, not into ~.
  export COOKIECUTTER_CONFIG="$run_dir/cookiecutter-config.yaml"
  printf 'cookiecutters_dir: "%s/cookiecutters/"\nreplay_dir: "%s/replay/"\n' \
    "$run_dir" "$run_dir" >"$COOKIECUTTER_CONFIG"

  build_copier_template "$tpl_dir/copier"
  build_cookiecutter_template "$tpl_dir/cookiecutter"
  if has_option yeoman; then
    build_yeoman_generator "$tpl_dir/yeoman-v1" 1
    build_yeoman_generator "$tpl_dir/yeoman-v2" 2
    ln -s "$node_modules" "$tpl_dir/node_modules"
  fi

  for option in $OPTIONS; do
    tpl="$(template_for "$option" "$tpl_dir")"
    measure_generation "$run" "$option" "$tpl" "$run_dir/$option-gen"
    measure_update "$run" "$option" "$tpl" "$run_dir/$option-update" "$logs"
  done
}

# Generates v1 twice (timed), and checks both copies are identical.
measure_generation() {
  local run=$1 option=$2 tpl=$3 base=$4 identical=yes stats seconds rss_kib
  stats="$base/stats"
  mkdir -p "$base/a" "$base/b"
  # /usr/bin/time cannot run a shell function: the script calls itself.
  timed "$stats" "$base/a.log" "$SELF" __generate "$option" 1 "$base/a/$PROJECT_NAME" "$tpl"
  generate "$option" 1 "$base/b/$PROJECT_NAME" "$tpl" >"$base/b.log" 2>&1
  diff -r -x .git "$base/a/$PROJECT_NAME" "$base/b/$PROJECT_NAME" >"$base/diff.txt" || identical=no
  read -r seconds rss_kib <"$stats"
  printf '%s\t%s\t%s\t%s\t%s\n' "$run" "$option" "$seconds" "$rss_kib" "$identical" \
    >>"$TRIAL_DIR/generation.tsv"
  log "run $run $option: generated in ${seconds}s, identical=$identical"
}

# For each update variant: fresh v1 project, local change, update to v2.
measure_update() {
  local run=$1 option=$2 tpl=$3 base=$4 logs=$5 variant project rc
  for variant in $(variants_for "$option"); do
    project="$base/$variant/$PROJECT_NAME"
    mkdir -p "$base/$variant"
    generate "$option" 1 "$project" "$tpl" >"$logs/$variant-generate.log" 2>&1
    make_local_change "$project"
    rc=0
    update "$variant" "$project" "$tpl" >"$logs/$variant-update.log" 2>&1 || rc=$?
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$run" "$variant" "$rc" \
      "$(classify_app_conf "$project")" "$(classify_pipeline "$project")" \
      "$(classify_notice "$project")" "$(classify_local_notes "$project")" \
      "$(unmerged_files "$project")" >>"$TRIAL_DIR/day2.tsv"
    log "run $run $variant: exit $rc"
  done
}

check_options() {
  local option
  for option in $OPTIONS; do
    case " $ALL_OPTIONS " in
      *" $option "*) ;;
      *) log "unknown option '$option', expected a subset of: $ALL_OPTIONS"; exit 2 ;;
    esac
  done
}

main() {
  local node_modules="" run
  # Internal entry point, used by measure_generation.
  if [[ "${1:-}" == "__generate" ]]; then
    shift
    generate "$@"
    return
  fi
  check_options
  # Default to a fresh private directory: a fixed path under /tmp could be
  # pre-created or symlinked by another local user. An explicit directory must
  # be missing or empty, so that no earlier content is mixed into the results.
  if [[ -n "${1:-}" ]]; then
    TRIAL_DIR="$1"
    if [[ -e "$TRIAL_DIR" && -n "$(ls -A "$TRIAL_DIR")" ]]; then
      log "refusing $TRIAL_DIR: it exists and is not empty"
      exit 2
    fi
    mkdir -p "$TRIAL_DIR"
  else
    TRIAL_DIR="$(mktemp -d)"
  fi
  TRIAL_DIR="$(cd "$TRIAL_DIR" && pwd)"
  # configstore (a yo dependency) writes under XDG_CONFIG_HOME.
  export XDG_CONFIG_HOME="$TRIAL_DIR/xdg-config"
  mkdir -p "$XDG_CONFIG_HOME"
  log "trial directory: $TRIAL_DIR"
  log "options: $OPTIONS"
  log "versions: copier $COPIER_VERSION, cookiecutter $COOKIECUTTER_VERSION," \
    "cruft $CRUFT_VERSION, yo $YO_VERSION, yeoman-generator $YEOMAN_GENERATOR_VERSION"

  # Warm the uv and npm caches so that timings exclude downloads.
  local node_version="not used"
  if has_option copier; then run_copier --version >/dev/null; fi
  if has_option cookiecutter; then run_cookiecutter --version >/dev/null; fi
  if has_option cruft; then run_cruft --help >/dev/null; fi
  if has_option yeoman; then
    node_modules="$(npx_node_modules)"
    node_version="$(node --version)"
  fi
  record_resolved_versions "$node_modules"
  log "git $(git --version | awk '{print $3}'), uv $(uv --version | awk '{print $2}')," \
    "python $UV_PYTHON (exclude-newer $UV_EXCLUDE_NEWER), node $node_version"

  printf 'run\toption\tseconds\tmax_rss_kib\tidentical\n' >"$TRIAL_DIR/generation.tsv"
  printf 'run\tvariant\texit\tapp.conf\tpipeline.yml\tNOTICE.txt\tlocal-notes.txt\tunmerged\n' \
    >"$TRIAL_DIR/day2.tsv"

  for run in $(seq 1 "$RUNS"); do
    run_once "$run" "$node_modules"
  done

  printf '\n== Generation (v1)\n'
  column -t -s "$(printf '\t')" "$TRIAL_DIR/generation.tsv"
  printf '\n== Day 2 (update v1 to v2 after a local change)\n'
  column -t -s "$(printf '\t')" "$TRIAL_DIR/day2.tsv"
}

main "$@"
