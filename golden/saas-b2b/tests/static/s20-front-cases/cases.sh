#!/usr/bin/env bash
# Test cases of the front part of control S20 (tests/static/s20-front-screens.sh).
#
# Each case copies the real front (src/, index.html, package.json) into a
# sandbox made by mktemp -d, adds or changes one file, runs the control on that
# front folder (its optional argument), and expects a failure that names the
# problem, or a pass. The control runs this file first when it has no
# argument, as it runs the tests of its policy. tests/run-static.sh does not
# run it directly: it lives in a subfolder and has no control header.
set -euo pipefail

here="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
control="$here/../s20-front-screens.sh"
real_front="$(CDPATH='' cd -- "$here/../../../src/front" && pwd)"

sandbox="$(mktemp -d)"
if [ -z "$sandbox" ] || [ ! -d "$sandbox" ]; then
  echo "mktemp -d gave no folder: S20 front tests stop." >&2
  exit 1
fi
trap 'rm -rf "$sandbox"' EXIT

cases=0
failures=0

# fresh_case <name>: copies the real front into <sandbox>/<name>/src/front
# and prints that folder.
fresh_case() {
  local dir="$sandbox/$1/src/front"
  mkdir -p "$dir"
  cp -R "$real_front/src" "$real_front/index.html" "$real_front/package.json" "$dir/"
  printf '%s' "$dir"
}

report() {
  failures=$((failures + 1))
  printf 'FAIL  S20 front case %s: %s\n' "$1" "$2" >&2
}

# expect_fail <name> <front folder> <text>: the control must exit non-zero
# and print <text>.
expect_fail() {
  local out status=0
  cases=$((cases + 1))
  out="$(bash "$control" "$2" 2>&1)" || status=$?
  if [ "$status" -eq 0 ]; then
    report "$1" "the control passed, it should have failed"
  elif ! printf '%s\n' "$out" | grep -q -F -e "$3"; then
    report "$1" "failed without the expected text '$3'; output: $out"
  fi
}

# expect_pass <name> <front folder>
expect_pass() {
  local out status=0
  cases=$((cases + 1))
  out="$(bash "$control" "$2" 2>&1)" || status=$?
  if [ "$status" -ne 0 ]; then
    report "$1" "the control failed, it should have passed; output: $out"
  fi
}

# refused <name> <file under the front folder> <text> <content>: a front
# with <content> written to <file> (replacing it) must fail with <text>.
refused() {
  local dir
  dir="$(fresh_case "$1")"
  mkdir -p "$(dirname "$dir/$2")"
  printf '%s\n' "$4" > "$dir/$2"
  expect_fail "$1" "$dir" "$3"
}

# refused_added <name> <file under src/> <text> <content>: the same, with the
# file added to the real front, which stays as it is.
refused_added() {
  local dir
  dir="$(fresh_case "$1")"
  mkdir -p "$(dirname "$dir/src/$2")"
  printf '%s\n' "$4" > "$dir/src/$2"
  expect_fail "$1" "$dir" "$3"
}

# accepted_added <name> <file under src/> <content>
accepted_added() {
  local dir
  dir="$(fresh_case "$1")"
  mkdir -p "$(dirname "$dir/src/$2")"
  printf '%s\n' "$3" > "$dir/src/$2"
  expect_pass "$1" "$dir"
}

if [ ! -f "$control" ]; then
  echo "$control is missing: S20 has no control to test." >&2
  exit 1
fi

nl=$'\n'

# The real front passes, unchanged.
expect_pass real-front "$(fresh_case real-front)"

# 1. Navigation, which the CSP does not stop either.
nav="navigates away"
refused_added nav-location-href-assign extra.ts "$nav" 'location.href = "/elsewhere";'
refused_added nav-window-location-href extra.ts "$nav" 'window.location.href = "/elsewhere";'
refused_added nav-location-assign extra.ts "$nav" 'location.assign("/elsewhere");'
refused_added nav-location-replace extra.ts "$nav" 'location.replace("/elsewhere");'
refused_added nav-location-bare-assignment extra.ts "$nav" 'location = "/elsewhere";'
refused_added nav-window-open extra.ts "$nav" 'window.open("/elsewhere");'
refused_added nav-document-location extra.ts "$nav" 'document.location = "/elsewhere";'
refused index-meta-refresh index.html "$nav" '<!doctype html>
<html lang="en"><head><meta http-equiv="refresh" content="0;url=/x" /></head>
<body><div id="root"></div><script type="module" src="/src/main.tsx"></script></body></html>'

# 2. WebRTC and WebTransport, which the CSP does not cover.
refused_added webrtc-peer-connection extra.ts "WebRTC" 'const peer = new RTCPeerConnection();'
refused_added webrtc-prefixed-peer-connection extra.ts "WebRTC" 'const peer = new webkitRTCPeerConnection();'
refused_added webrtc-data-channel extra.ts "WebRTC" 'declare const channel: RTCDataChannel;'
refused_added webtransport extra.ts "WebTransport" 'const t = new WebTransport("/x");'

# 3. An address with no scheme: "//host".
nos="no scheme"
refused_added protocol-relative-double-quotes extra.ts "$nos" 'export const a = "//cdn.example.test/x.js";'
refused_added protocol-relative-single-quotes extra.ts "$nos" "export const a = '//cdn.example.test/x.js';"
# shellcheck disable=SC2016  # the trap is source text, `${1}` must not expand
refused_added protocol-relative-template extra.ts "$nos" 'export const a = `//cdn.example.test/${1}`;'
refused_added protocol-relative-in-tsx extra.tsx "$nos" 'export const a = <img src="//cdn.example.test/x.png" />;'
refused_added protocol-relative-css-url styles2.css "$nos" 'body { background: url(//cdn.example.test/x.png); }'
refused_added protocol-relative-css-import styles2.css "$nos" '@import "//cdn.example.test/x.css";'
refused_added protocol-relative-css-import-url styles2.css "$nos" '@import url(//cdn.example.test/x.css);'
refused index-protocol-relative-script index.html "$nos" '<!doctype html>
<html lang="en"><head></head>
<body><div id="root"></div><script src="//cdn.example.test/x.js"></script></body></html>'

# 4. fetch, or another channel, through an alias.
alias_text="fetch outside the client of the contract"
refused_added alias-const-outside-client extra.ts "$alias_text" 'const f = fetch;'
refused_added alias-globalthis-outside-client extra.ts "$alias_text" 'export const g = globalThis.fetch;'
refused_added alias-window-outside-client extra.ts "$alias_text" 'export const g = window.fetch.bind(window);'
refused_added alias-destructuring-outside-client extra.ts "$alias_text" 'const { fetch: f } = window;'
refused_added alias-bracket-window extra.ts "by name in a string" 'export const g = window["fetch"];'
refused_added alias-bracket-single-quotes extra.ts "by name in a string" "export const g = globalThis['fetch'];"
refused_added alias-bracket-websocket extra.ts "by name in a string" 'export const g = window["WebSocket"];'
refused_added alias-bracket-open extra.ts "by name in a string" 'window["open"]("/x");'
refused_added alias-reflect-get extra.ts "by name in a string" 'export const g = Reflect.get(window, "fetch");'
dir="$(fresh_case alias-const-in-client)"
printf 'const f = fetch;\n' >> "$dir/src/api.ts"
expect_fail alias-const-in-client "$dir" "other than as a direct call"
dir="$(fresh_case alias-bind-in-client)"
printf 'export const g = fetch.bind(window);\n' >> "$dir/src/api.ts"
expect_fail alias-bind-in-client "$dir" "other than as a direct call"
accepted_added word-fetch-in-a-string-or-name extra.ts 'export const message = "Could not fetch the notes"; export function fetchNotes(): void {}'

# 5. Comments: a line that carries code after the end of a comment is read.
refused_added comment-block-then-code extra.ts "network channel other than fetch" '/* note */ const s = new WebSocket("/x");'
refused_added comment-block-lines-then-code extra.ts "network channel other than fetch" "/*${nl} * note${nl} */ const s = new WebSocket(\"/x\");"
refused_added comment-star-line-with-code extra.ts "network channel other than fetch" "/* a${nl}*/ const s = new WebSocket(\"/x\");"
refused_added comment-block-between-code extra.ts "network channel other than fetch" 'const s = /* note */ new WebSocket("/x");'
refused_added comment-code-before-line-comment extra.ts "network channel other than fetch" 'const s = new WebSocket("/x"); // note'
refused_added comment-line-comment-marker-in-a-string extra.ts "network channel other than fetch" 'const u = "a//b"; const s = new WebSocket("/x");'
accepted_added comment-words-in-comments extra.ts "// WebSocket and location.href are not used here${nl}/*${nl} * RTCPeerConnection, https://example.test, fetch${nl} */${nl}export const ok = 1; /* window.open( */"

# 6. Files other than .ts and .tsx.
ws='export const s = new WebSocket("/x");'
refused_added file-js extra.js "network channel other than fetch" "$ws"
refused_added file-jsx extra.jsx "network channel other than fetch" "$ws"
refused_added file-mjs extra.mjs "network channel other than fetch" "$ws"
refused_added file-cjs extra.cjs "network channel other than fetch" "$ws"
refused_added file-css-url-other-host extra.css "names an absolute address" 'body { background: url(https://cdn.example.test/x.png); }'
refused_added file-css-quoted-url-other-host extra.css "names an absolute address" 'body { background: url("https://cdn.example.test/x.png"); }'
refused_added file-css-import-other-host extra.css "names an absolute address" '@import url("https://cdn.example.test/x.css");'
refused_added file-html-in-src extra.html "names an absolute address" '<img src="https://cdn.example.test/x.png" />'
refused index-script-other-host index.html "names an absolute address" '<!doctype html>
<html lang="en"><head></head>
<body><div id="root"></div><script src="https://cdn.example.test/x.js"></script></body></html>'
accepted_added file-css-relative-url extra.css 'body { background: url(/img/x.png); } /* url(https://cdn.example.test/x.png) */'
accepted_added file-test-files-are-left-out extra.test.ts "$ws"

# 7. A bare import outside the closed list, a devDependency for example.
imp="imports "
refused_added import-dev-dependency extra.ts "${imp}vite" 'import { defineConfig } from "vite";'
refused_added import-dev-dependency-single-quotes extra.ts "${imp}vitest" "import { test } from 'vitest';"
refused_added import-scoped-dev-dependency extra.ts "${imp}@testing-library/react" 'import { render } from "@testing-library/react";'
refused_added import-side-effect extra.ts "${imp}jsdom" 'import "jsdom";'
refused_added import-multi-line extra.ts "${imp}vitest" "import {${nl}  test,${nl}  expect,${nl}} from \"vitest\";"
refused_added import-export-from extra.ts "${imp}lodash" 'export { debounce } from "lodash";'
refused_added import-dynamic extra.ts "${imp}lodash" 'export const load = () => import("lodash");'
refused_added import-require extra.cjs "${imp}axios" 'const axios = require("axios");'
refused_added import-css extra.css "${imp}tailwindcss" '@import "tailwindcss";'
refused_added import-react-subpath-not-listed extra.ts "${imp}react-dom/server" 'import { renderToString } from "react-dom/server";'
refused_added import-dynamic-computed extra.ts "dynamic import" 'export const load = (name: string) => import(name);'
accepted_added import-closed-list extra.tsx 'import { jsx } from "react/jsx-runtime"; import { useState } from "react"; import { createRoot } from "react-dom/client"; import { x } from "./other"; import "../src/styles.css";'

if [ "$failures" -gt 0 ]; then
  printf '%s of %s S20 front case(s) failed.\n' "$failures" "$cases" >&2
  exit 1
fi
printf 'All %s S20 front case(s) passed.\n' "$cases"
