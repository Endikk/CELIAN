#!/usr/bin/env bash
# control: S20
# carries: FR-009
#
# The front has one screen, the notes screen, and calls only the routes of
# the API contract, by relative paths, with no other network channel. Reads
# the sources of src/front/src/ (tests left out), writes what it finds into
# a facts file, then runs the tests of policy package front_screens and the
# policy on the facts, on src/front/package.json and on the list of contract
# routes, tests/static/s20-contract-routes.yaml, which s20-api-routes.sh
# keeps equal to the contract.
#
# Convention of the sources, which this check enforces: every route the
# front calls is a string literal "<METHOD> <path>" (src/api.ts), and fetch
# is called in src/api.ts only. A string that starts with /api outside such
# a literal fails the check. Comment lines are skipped.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"

front="src/front"
sources="$front/src"
routes_file="tests/static/s20-contract-routes.yaml"
client="$sources/api.ts"

if ! command -v conftest >/dev/null 2>&1; then
  echo "conftest is not installed: run tests/tools/install.sh <dir>, then put <dir> on PATH." >&2
  exit 1
fi

for file in "$front/package.json" "$routes_file"; do
  if [ ! -f "$file" ]; then
    echo "$file is missing: S20 checks the front against the routes of the API contract." >&2
    exit 1
  fi
done
if [ ! -d "$sources" ]; then
  echo "$sources is missing: the notes screen of the front lives there (spec 001, T030)." >&2
  exit 1
fi

# A quote of any kind, then anything but a quote: the bounds of a literal.
q='["'"'"'`]'
nq='[^"'"'"'`]'
route_literal="${q}(GET|PUT|POST|DELETE|PATCH|HEAD|OPTIONS) /api${nq}*${q}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
facts="$tmp/s20-front-facts.yaml"

# "<number>:<text>" for each line of file $1 that is not a comment line.
code_lines() {
  grep -n -v -E -e '^[[:space:]]*(//|/\*|\*)' "$1" || true
}

# Appends value $2 to the list file $tmp/$1, quoted for YAML.
add() {
  printf "  - '%s'\n" "$(printf '%s' "$2" | sed -e "s/'/''/g")" >> "$tmp/$1"
}

for list in screens html_entries calls stray_api forbidden; do
  : > "$tmp/$list"
done

if [ -d "$sources/screens" ]; then
  while IFS= read -r file; do
    add screens "${file#"$sources/screens/"}"
  done < <(find "$sources/screens" -type f | LC_ALL=C sort)
fi

while IFS= read -r file; do
  add html_entries "${file#"$front/"}"
done < <(find "$front" \( -name node_modules -o -name dist \) -prune -o -type f -name '*.html' -print | LC_ALL=C sort)

# Channels and settings the front must not use, as "<fixed string>|<reason>".
forbidden_uses="://|names an absolute address; the front calls relative paths only
import.meta.env|uses import.meta.env, a configured value; the front has no configured address
XMLHttpRequest|opens a network channel other than fetch on the contract routes
WebSocket|opens a network channel other than fetch on the contract routes
EventSource|opens a network channel other than fetch on the contract routes
sendBeacon|opens a network channel other than fetch on the contract routes
pushState|navigates to another screen; the front has one
replaceState|navigates to another screen; the front has one"

while IFS= read -r file; do
  lines="$(code_lines "$file")"
  [ -n "$lines" ] || continue
  while IFS= read -r entry; do
    number="${entry%%:*}"
    text="${entry#*:}"
    case "$text" in
      */api*)
        while IFS= read -r literal; do
          [ -n "$literal" ] || continue
          literal="${literal#?}"
          add calls "${literal%?}"
        done < <(printf '%s\n' "$text" | grep -o -E -e "$route_literal" || true)
        if printf '%s\n' "$text" | sed -E -e "s#${route_literal}##g" | grep -q -E -e "${q}/api"; then
          add stray_api "$file:$number"
        fi
        ;;
    esac
    while IFS='|' read -r token reason; do
      case "$text" in
        *"$token"*) add forbidden "$file:$number: $reason" ;;
      esac
    done < <(printf '%s\n' "$forbidden_uses")
    if [ "$file" != "$client" ]; then
      case "$text" in
        *"fetch("*) add forbidden "$file:$number: calls fetch outside $client, the client of the contract" ;;
      esac
    fi
  done < <(printf '%s\n' "$lines")
done < <(find "$sources" -type f \( -name '*.ts' -o -name '*.tsx' \) ! -name '*.test.ts' ! -name '*.test.tsx' | LC_ALL=C sort)

: > "$facts"
for list in screens html_entries calls stray_api forbidden; do
  if [ -s "$tmp/$list" ]; then
    printf '%s:\n' "$list" >> "$facts"
    cat "$tmp/$list" >> "$facts"
  else
    printf '%s: []\n' "$list" >> "$facts"
  fi
done

conftest verify --no-color --policy policy --namespace front_screens
conftest test --no-color --combine --policy policy --namespace front_screens "$front/package.json" "$routes_file" "$facts"
