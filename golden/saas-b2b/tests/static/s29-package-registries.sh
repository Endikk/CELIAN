#!/usr/bin/env bash
# control: S29
# carries: FR-013; constitution, principle VI; ADR-016, condition 1
#
# The package managers of the golden repo read one registry each, the public
# one, and no credential. Renovate reads the .npmrc and the nuget.config of
# the repository to find where to look up versions: a registry or a package
# source on another host would send its searches to a registry that dates its
# versions as it likes, and would defeat the 7 days delay (constitution,
# principle VI). Finds every .npmrc and every nuget.config (any letter case,
# so NuGet.Config too) under the root, and refuses:
# - in a .npmrc, a registry or @scope:registry key whose value is not exactly
#   https://registry.npmjs.org/, and any authentication key: _auth,
#   _authToken, _password, username, email, alone or scoped by a
#   //host/path/: prefix;
# - in a nuget.config, an <add> of packageSources whose value is not exactly
#   https://api.nuget.org/v3/index.json, a packageSources without <clear />
#   (which would keep the sources of the user and machine configuration), and
#   any packageSourceCredentials section, even an empty one.
#
# Sources, read on 2026-11-25:
# - .npmrc: https://docs.npmjs.com/cli/v11/configuring-npm/npmrc (INI format
#   of key = value pairs, comments start with ; or #, scoped registry written
#   @scope:registry, authentication keys scoped by a //host/: prefix and
#   listed as _auth, _authToken, username, _password, email);
#   https://docs.npmjs.com/cli/v11/using-npm/config (registry, default
#   https://registry.npmjs.org/).
# - nuget.config: https://learn.microsoft.com/en-us/nuget/reference/nuget-config-file
#   (XML, names case-insensitive; packageSources holds <add key= value= />
#   and <clear />; packageSourceCredentials holds the credentials; the source
#   of nuget.org is https://api.nuget.org/v3/index.json).
# Renovate reading these files: lib/modules/datasource/npm/npmrc.ts and
# lib/modules/manager/nuget/util.ts, Renovate 44.247.1 ([SECU] review of PR #61).
#
# Usage: s29-package-registries.sh [root]. Without an argument the root is
# the golden repo. With one, only that folder is scanned: the test cases use
# it (tests/static/s29-cases/cases.sh, which this control runs first when it
# has no argument, as S20 runs its policy tests).
set -euo pipefail

npm_registry='https://registry.npmjs.org/'
nuget_source='https://api.nuget.org/v3/index.json'

if [ "$#" -gt 1 ]; then
  echo "usage: s29-package-registries.sh [root]" >&2
  exit 2
fi

here="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [ "$#" -eq 1 ]; then
  root="$(CDPATH='' cd -- "$1" && pwd)"
else
  root="$(CDPATH='' cd -- "$here/../.." && pwd)"
  bash "$here/s29-cases/cases.sh"
fi
CDPATH='' cd -- "$root"

failed=0

refuse() {
  failed=$((failed + 1))
  printf '%s: %s\n' "$1" "$2"
}

# Removes the leading and trailing white space of $1.
trim() {
  local text="$1"
  text="${text#"${text%%[![:space:]]*}"}"
  text="${text%"${text##*[![:space:]]}"}"
  printf '%s' "$text"
}

check_npmrc() {
  local label="$1" line key value base
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line="$(trim "$line")"
    case "$line" in
      '' | ';'* | '#'*) continue ;;
      *=*) ;;
      *) continue ;;
    esac
    key="$(trim "${line%%=*}")"
    value="$(trim "${line#*=}")"
    case "$value" in
      \"*\") value="${value#\"}"; value="${value%\"}" ;;
    esac
    base="${key##*:}"
    case "$base" in
      registry)
        if [ "$key" != "registry" ] && [ "${key#@}" = "$key" ]; then
          refuse "$label" "registry key $key is not a registry or @scope:registry key"
        elif [ "$value" != "$npm_registry" ]; then
          refuse "$label" "registry key $key points to '$value', not exactly $npm_registry"
        fi
        ;;
      _auth | _authToken | _password | username | email)
        refuse "$label" "authentication key $key; a credential does not belong in the repository"
        ;;
    esac
  done < "$1"
}

# Prints one problem per line for nuget.config file $1, as "<message>".
nuget_problems() {
  tr '\n\r' '  ' < "$1" | awk -v allowed="$nuget_source" '
    {
      text = $0
      out = ""
      while ((i = index(text, "<!--")) > 0) {
        out = out substr(text, 1, i - 1)
        text = substr(text, i + 4)
        j = index(text, "-->")
        if (j == 0) { print "unterminated XML comment"; text = ""; break }
        text = substr(text, j + 3)
      }
      out = out text
      gsub(/</, "\n<", out)
      n = split(out, tags, "\n")
      in_sources = 0
      seen_sources = 0
      cleared = 0
      for (k = 1; k <= n; k++) {
        tag = tags[k]
        low = tolower(tag)
        if (low ~ /^<packagesourcecredentials[ \/>]/) {
          print "packageSourceCredentials section; a credential does not belong in the repository"
        } else if (low ~ /^<packagesources[ \/>]/) {
          if (in_sources && !cleared) { print "packageSources has no <clear />" }
          seen_sources = 1
          cleared = 0
          in_sources = (low !~ /\/>[ ]*$/)
          if (!in_sources) { print "packageSources has no <clear />" }
        } else if (low ~ /^<\/packagesources[ >]/) {
          if (in_sources && !cleared) { print "packageSources has no <clear />" }
          in_sources = 0
        } else if (in_sources && low ~ /^<clear[ \/>]/) {
          cleared = 1
        } else if (in_sources && low ~ /^<add[ \/>]/) {
          if (match(low, /value[ ]*=[ ]*["\047]/)) {
            rest = substr(tag, RSTART + RLENGTH - 1)
            quote = substr(rest, 1, 1)
            rest = substr(rest, 2)
            end = index(rest, quote)
            value = (end > 0) ? substr(rest, 1, end - 1) : rest
            if (value != allowed) { print "package source " value ", not exactly " allowed }
          } else {
            print "package source <add> with no value attribute"
          }
        }
      }
      if (in_sources && !cleared) { print "packageSources has no <clear />" }
    }
  '
}

check_nuget() {
  local file="$1" message
  while IFS= read -r message; do
    [ -n "$message" ] || continue
    refuse "$file" "$message"
  done < <(nuget_problems "$file")
}

found=0
while IFS= read -r path; do
  file="${path#./}"
  found=$((found + 1))
  case "$(basename -- "$file")" in
    .npmrc) check_npmrc "$file" ;;
    *) check_nuget "$file" ;;
  esac
done < <(find . \( -name .git -o -name node_modules -o -name dist -o -name bin -o -name obj \) -prune \
  -o -type f \( -name .npmrc -o -iname nuget.config \) -print | LC_ALL=C sort)

if [ "$failed" -gt 0 ]; then
  exit 1
fi
printf 'S29: %s package manager configuration file(s), only the public registries.\n' "$found"
