#!/usr/bin/env bash
# Checks the "# renovate:" comments of the workflows. The preset
# customManagers:githubActionsVersions, which both renovate.json extend,
# reads these fields in such a comment (renovatebot/renovate, tag 44.247.1,
# lib/config/presets/internal/custom-managers.preset.ts): datasource,
# depName, lookupName or packageName, versioning, extractVersion and
# registryUrl. Renovate would then look a version up in a registry that the
# comment names, and S23 does not see presets. A comment of a workflow sets
# datasource and depName only, and the datasource is one of those in use:
# github-releases, pypi and docker. Any other key is refused, the five above
# by name. Called by tests/static/s23-renovate.sh, and in CELIAN by
# scripts/renovate/check-renovate.sh. One program shared by both.
#
# Usage: tests/tools/check-renovate-workflow-comments.sh <workflow>...
#        tests/tools/check-renovate-workflow-comments.sh --cases <directory>
# With --cases, each *.yml of the directory is a failing case: it must be
# refused, and the output must hold the text of its "# expect:" line.
set -euo pipefail

self="${BASH_SOURCE[0]}"

if [ "$#" -eq 0 ]; then
  echo "usage: tests/tools/check-renovate-workflow-comments.sh <workflow>... | --cases <directory>" >&2
  exit 1
fi

# Runs the failing cases of directory $1 through this script.
check_cases() {
  local dir="$1" case_file expect out found=0 problems=0
  [ -d "$dir" ] || {
    echo "check-renovate-workflow-comments.sh: $dir is missing." >&2
    exit 1
  }
  for case_file in "$dir"/*.yml; do
    [ -f "$case_file" ] || continue
    found=$((found + 1))
    expect="$(awk -v key='# expect: ' 'NR > 10 { exit } index($0, key) == 1 { print substr($0, length(key) + 1); exit }' "$case_file")"
    if [ -z "$expect" ]; then
      echo "$case_file: no '# expect:' line" >&2
      problems=$((problems + 1))
    elif out="$(bash "$self" "$case_file" 2>&1)"; then
      echo "$case_file: accepted, yet it is a failing case: $expect" >&2
      problems=$((problems + 1))
    elif ! printf '%s\n' "$out" | grep -F -q -e "$expect"; then
      echo "$case_file: refused, but no message holds: $expect" >&2
      problems=$((problems + 1))
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo "$dir holds no failing case." >&2
    problems=$((problems + 1))
  fi
  [ "$problems" -eq 0 ]
}

if [ "$1" = "--cases" ]; then
  [ "$#" -eq 2 ] || {
    echo "usage: tests/tools/check-renovate-workflow-comments.sh --cases <directory>" >&2
    exit 1
  }
  check_cases "$2"
  exit 0
fi

for file in "$@"; do
  if [ ! -f "$file" ]; then
    echo "check-renovate-workflow-comments.sh: $file is missing." >&2
    exit 1
  fi
done

# A comment is any line with "renovate:" after a "#", wherever it sits on the
# line: the regex of the preset is not anchored to the start of a line. The
# words after it are key=value pairs; the value of a key ends at a space.
awk '
  function refuse(message) {
    printf "%s, line %d: %s\n", FILENAME, FNR, message
    bad++
  }
  /#[[:space:]]*renovate:/ {
    seen++
    text = $0
    sub(/^.*#[[:space:]]*renovate:/, "", text)
    count = split(text, words, /[[:space:]]+/)
    has_datasource = 0
    has_depname = 0
    for (i = 1; i <= count; i++) {
      word = words[i]
      if (word == "") continue
      eq = index(word, "=")
      if (eq == 0) {
        refuse("\"renovate:\" comment holds \"" word "\", which is not key=value")
        continue
      }
      key = substr(word, 1, eq - 1)
      value = substr(word, eq + 1)
      if (key == "datasource") {
        has_datasource = 1
        if (value != "github-releases" && value != "pypi" && value != "docker")
          refuse("\"renovate:\" comment sets datasource=" value ", and only github-releases, pypi and docker are in use")
      } else if (key == "depName") {
        has_depname = 1
      } else if (key == "packageName" || key == "lookupName" || key == "registryUrl" || \
                 key == "extractVersion" || key == "versioning") {
        refuse("\"renovate:\" comment sets " key ", which the preset githubActionsVersions reads to name a package, a registry or a version format; the workflows set datasource and depName only")
      } else {
        refuse("\"renovate:\" comment sets " key ", and the workflows set datasource and depName only")
      }
    }
    if (!has_datasource || !has_depname)
      refuse("\"renovate:\" comment has no datasource= and depName=")
  }
  END {
    if (bad > 0) exit 1
  }
' "$@" >&2
