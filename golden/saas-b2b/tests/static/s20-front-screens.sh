#!/usr/bin/env bash
# control: S20
# carries: FR-009
#
# The real network barrier of the front is the Content-Security-Policy of
# src/front/nginx.conf. S20 checks the contract and catches mistakes, it does
# not replace that policy: a text scan cannot see a channel that code builds
# at run time (a name assembled from pieces, eval, a computed URL in
# src/api.ts), and the CSP covers neither navigation nor WebRTC nor
# WebTransport, which this scan refuses by name.
#
# The front has one screen, the notes screen, and calls only the routes of
# the API contract, by relative paths, with no other network channel. Reads
# the sources of src/front/src/ (.ts .tsx .js .jsx .mjs .cjs .css .html, tests
# left out) and every .html file of src/front/, writes what it finds into a
# facts file, then runs the tests of policy package front_screens and the
# policy on the facts, on src/front/package.json and on the list of contract
# routes, tests/static/s20-contract-routes.yaml, which s20-api-routes.sh
# keeps equal to the contract.
#
# Convention of the sources, which this check enforces: every route the
# front calls is a string literal "<METHOD> <path>" (src/api.ts), and fetch
# appears in src/api.ts only, and there only as a direct call. A string that
# starts with /api outside such a literal fails the check. Comments are
# removed first, block and line comments alike, so that a line which carries
# code after the end of a comment is still read. Strings are kept: a scanner
# cannot tell a regular expression that holds a quote from the start of a
# string, and the one that ends at the end of its line is the least costly
# mistake.
#
# Left open on purpose, because no text scan closes them without false
# positives: a name built from pieces ("fe" + "tch"), eval and Function, a
# regular expression literal that holds a quote and so hides what follows it
# on the same line, a URL computed in src/api.ts, an address in a file type
# not listed above (.svg, .json). The CSP answers for them.
#
# Usage: s20-front-screens.sh [front folder]. Without an argument the control
# reads the front of the golden repo, runs the test cases of
# tests/static/s20-front-cases/ and the tests of its policy. With one, it
# reads that front folder only: the test cases use it.
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "usage: s20-front-screens.sh [front folder]" >&2
  exit 2
fi

here="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(CDPATH='' cd -- "$here/../.." && pwd)"
CDPATH='' cd -- "$root"

if [ "$#" -eq 1 ]; then
  front="$(CDPATH='' cd -- "$1" && pwd)"
  run_tests=0
else
  front="src/front"
  run_tests=1
  bash "$here/s20-front-cases/cases.sh"
fi
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
# A character that cannot be part of an identifier, or the edge of the line.
before='(^|[^A-Za-z0-9_$])'
after='([^A-Za-z0-9_$]|$)'

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
facts="$tmp/s20-front-facts.yaml"
code_view="$tmp/code-view.txt"
bare_view="$tmp/bare-view.txt"

# Appends value $2 to the list file $tmp/$1, quoted for YAML.
add() {
  printf "  - '%s'\n" "$(printf '%s' "$2" | sed -e "s/'/''/g")" >> "$tmp/$1"
}

# Prints file $3 line by line, same line numbers, without its comments. $1 is
# the kind of file: js (// and /* */ comments, ' " and ` strings), css (/* */
# comments, ' and " strings) or html (<!-- --> comments, no strings). $2 is 1
# to also empty the content of ' and " strings, which leaves the quotes: the
# view on which names are searched, so that a word in a sentence of the page
# is not taken for code. A ' or " string ends at the end of its line.
strip_comments() {
  awk -v kind="$1" -v blank="$2" '
    BEGIN { state = "code"; bq = "\047"; dq = "\042" }
    {
      line = $0; out = ""; n = length(line); i = 1
      while (i <= n) {
        c = substr(line, i, 1); two = substr(line, i, 2)
        if (state == "block") {
          if (two == "*/") { state = "code"; out = out " "; i += 2 } else { i++ }
        } else if (state == "html") {
          if (substr(line, i, 3) == "-->") { state = "code"; out = out " "; i += 3 } else { i++ }
        } else if (state == "string") {
          if (c == "\\") {
            if (!blank || quote == "`") { out = out two }
            i += 2
          } else if (c == quote) {
            state = "code"; out = out c; i++
          } else {
            if (!blank || quote == "`") { out = out c }
            i++
          }
        } else if (kind != "html" && two == "/*") {
          state = "block"; out = out " "; i += 2
        } else if (kind == "js" && two == "//") {
          i = n + 1
        } else if (kind == "html" && substr(line, i, 4) == "<!--") {
          state = "html"; out = out " "; i += 4
        } else if (kind != "html" && (c == bq || c == dq || (kind == "js" && c == "`"))) {
          state = "string"; quote = c; out = out c; i++
        } else {
          out = out c; i++
        }
      }
      if (state == "string" && quote != "`") { state = "code" }
      print out
    }' "$3"
}

# kind_of <file>: js, css or html.
kind_of() {
  case "$1" in
    *.css) printf 'css' ;;
    *.html) printf 'html' ;;
    *) printf 'js' ;;
  esac
}

# flag <view file> <ERE> <reason>: a "<file>:<line>: <reason>" entry for each
# line of the view that matches. $file is the file being read.
flag() {
  local number rest
  while IFS=: read -r number rest; do
    [ -n "$number" ] || continue
    add forbidden "$file:$number: $3"
  done < <(grep -n -E -e "$2" "$1" || true)
}

for list in screens html_entries calls stray_api forbidden imports; do
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

# Channels the front must not use, as "<fixed string>|<reason>", searched in
# the code view. A channel that the CSP does not cover is named as such.
forbidden_uses="import.meta.env|uses import.meta.env, a configured value; the front has no configured address
XMLHttpRequest|opens a network channel other than fetch on the contract routes
WebSocket|opens a network channel other than fetch on the contract routes
EventSource|opens a network channel other than fetch on the contract routes
sendBeacon|opens a network channel other than fetch on the contract routes
RTCPeerConnection|opens a WebRTC channel, which the CSP does not cover
RTCDataChannel|opens a WebRTC channel, which the CSP does not cover
WebTransport|opens a WebTransport channel, which the CSP does not cover
pushState|navigates to another screen; the front has one
replaceState|navigates to another screen; the front has one"

nav_reason="navigates away from the page, which the CSP does not stop"
names='fetch|open|location|XMLHttpRequest|WebSocket|EventSource|sendBeacon|RTCPeerConnection|RTCDataChannel|WebTransport|pushState|replaceState'

# Checks of one file, on its two views.
scan_file() {
  local kind entry number text literal spec token reason literal_import
  kind="$(kind_of "$file")"
  strip_comments "$kind" 0 "$file" > "$code_view"
  strip_comments "$kind" 1 "$file" > "$bare_view"

  flag "$code_view" '://' "names an absolute address; the front calls relative paths only"
  flag "$code_view" "${q}//|[(=][[:space:]]*//" "names an address with no scheme (//host); the front calls relative paths only"
  flag "$code_view" "${q}(${names})${q}" "reaches a network or navigation API by name in a string"
  flag "$code_view" "[Hh][Tt][Tt][Pp]-[Ee][Qq][Uu][Ii][Vv]" "$nav_reason (http-equiv refresh)"
  flag "$code_view" "${before}import[[:space:]]*\\([[:space:]]*[^\"'\`[:space:])]" "uses a dynamic import with a specifier that is not a literal"
  while IFS='|' read -r token reason; do
    flag "$code_view" "$(printf '%s' "$token" | sed -e 's/\./\\./g')" "$reason"
  done < <(printf '%s\n' "$forbidden_uses")

  flag "$bare_view" "${before}location${after}" "$nav_reason (location)"
  flag "$bare_view" "${before}open[[:space:]]*\\(" "$nav_reason (open)"
  if [ "$file" != "$client" ]; then
    flag "$bare_view" "${before}fetch${after}" "uses fetch outside the client of the contract (src/api.ts)"
  else
    sed -e 's/fetch[[:space:]][[:space:]]*(/fetch(/g' "$bare_view" > "$bare_view.tight"
    flag "$bare_view.tight" "${before}fetch([^(A-Za-z0-9_$]|$)" "uses fetch other than as a direct call"
  fi

  while IFS= read -r entry; do
    number="${entry%%:*}"
    text="${entry#*:}"
    while IFS= read -r literal; do
      [ -n "$literal" ] || continue
      literal="${literal#?}"
      add calls "${literal%?}"
    done < <(printf '%s\n' "$text" | grep -o -E -e "$route_literal" || true)
    if printf '%s\n' "$text" | sed -E -e "s#${route_literal}##g" | grep -q -E -e "${q}/api"; then
      add stray_api "$file:$number"
    fi
  done < <(grep -n -F -e '/api' "$code_view" || true)

  # Bare imports: "<specifier> <file>:<line>", compared by the policy to a
  # closed list. Relative and absolute paths stay on the origin.
  case "$kind" in
    js) literal_import="(from|import|import[[:space:]]*\\(|require[[:space:]]*\\()[[:space:]]*${q}${nq}*${q}" ;;
    css) literal_import="@import[[:space:]]+(url\\([[:space:]]*)?${q}${nq}*${q}" ;;
    *) return 0 ;;
  esac
  while IFS= read -r entry; do
    number="${entry%%:*}"
    spec="${entry#*:}"
    spec="$(printf '%s' "$spec" | sed -e "s/^[^\"'\`]*[\"'\`]//" -e "s/[\"'\`]\$//")"
    case "$spec" in
      '' | .* | /*) ;;
      *) add imports "$spec $file:$number" ;;
    esac
  done < <(grep -n -o -E -e "$literal_import" "$code_view" || true)
}

while IFS= read -r file; do
  scan_file
done < <(
  {
    find "$sources" -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.css' -o -name '*.html' \) ! -name '*.test.*'
    find "$front" \( -name node_modules -o -name dist \) -prune -o -type f -name '*.html' -print
  } | LC_ALL=C sort -u
)

: > "$facts"
for list in screens html_entries calls stray_api forbidden imports; do
  if [ -s "$tmp/$list" ]; then
    printf '%s:\n' "$list" >> "$facts"
    cat "$tmp/$list" >> "$facts"
  else
    printf '%s: []\n' "$list" >> "$facts"
  fi
done

if [ "$run_tests" -eq 1 ]; then
  conftest verify --no-color --policy policy --namespace front_screens
fi
conftest test --no-color --combine --policy policy --namespace front_screens "$front/package.json" "$routes_file" "$facts"
