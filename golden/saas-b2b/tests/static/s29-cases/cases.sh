#!/usr/bin/env bash
# Test cases of control S29 (tests/static/s29-package-registries.sh).
#
# Each case writes a package manager configuration file into a sandbox made
# by mktemp -d, runs the control on that folder (its optional argument is
# the root to scan), and expects a failure that names the problem, or a
# pass. The control runs this file first, as S20 runs the tests of its
# policy before the policy. tests/run-static.sh does not run it directly: it
# lives in a subfolder and has no control header.
set -euo pipefail

here="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
control="$here/../s29-package-registries.sh"

sandbox="$(mktemp -d)"
if [ -z "$sandbox" ] || [ ! -d "$sandbox" ]; then
  echo "mktemp -d gave no folder: S29 tests stop." >&2
  exit 1
fi
trap 'rm -rf "$sandbox"' EXIT

npm_ok='https://registry.npmjs.org/'
nuget_ok='https://api.nuget.org/v3/index.json'
cases=0
failures=0

# new_case <name>: makes an empty root for the case and prints its path.
new_case() {
  local dir="$sandbox/$1"
  mkdir -p "$dir"
  printf '%s' "$dir"
}

# nuget_file <path> <sources body>: a nuget.config whose packageSources hold $2.
nuget_file() {
  printf '<?xml version="1.0" encoding="utf-8"?>\n<configuration>\n  <packageSources>\n%s\n  </packageSources>\n</configuration>\n' "$2" > "$1"
}

report() {
  failures=$((failures + 1))
  printf 'FAIL  S29 case %s: %s\n' "$1" "$2" >&2
}

# expect_fail <name> <root> <text>: the control must exit non-zero and print <text>.
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

# expect_pass <name> <root>
expect_pass() {
  local out status=0
  cases=$((cases + 1))
  out="$(bash "$control" "$2" 2>&1)" || status=$?
  if [ "$status" -ne 0 ]; then
    report "$1" "the control failed, it should have passed; output: $out"
  fi
}

if [ ! -f "$control" ]; then
  echo "$control is missing: S29 has no control to test." >&2
  exit 1
fi

# npm: refused.
d="$(new_case npm-third-party-registry)"
printf 'registry=https://registry.example.test/\n' > "$d/.npmrc"
expect_fail npm-third-party-registry "$d" ".npmrc: registry"

d="$(new_case npm-registry-lookalike)"
printf 'registry = https://registry.npmjs.org.example.test/\n' > "$d/.npmrc"
expect_fail npm-registry-lookalike "$d" ".npmrc: registry"

d="$(new_case npm-registry-no-slash)"
printf 'registry=https://registry.npmjs.org\n' > "$d/.npmrc"
expect_fail npm-registry-no-slash "$d" ".npmrc: registry"

d="$(new_case npm-scoped-registry)"
printf '@acme:registry=https://npm.example.test/\n' > "$d/.npmrc"
expect_fail npm-scoped-registry "$d" "@acme:registry"

d="$(new_case npm-scoped-registry-in-subfolder)"
mkdir -p "$d/src/front"
printf '# comment\n@acme:registry=https://npm.example.test/\n' > "$d/src/front/.npmrc"
expect_fail npm-scoped-registry-in-subfolder "$d" "src/front/.npmrc: registry key @acme:registry"

for key in '_auth' '_authToken' '_password' 'username' 'email' \
  '//registry.npmjs.org/:_authToken' '//npm.example.test/:_auth' \
  '//npm.example.test/org/:_password'; do
  d="$(new_case "npm-auth-$key")"
  printf '%s=value\n' "$key" > "$d/.npmrc"
  expect_fail "npm-auth-$key" "$d" ".npmrc: authentication key $key"
done

d="$(new_case npm-auth-after-good-lines)"
printf 'ignore-scripts=true\nregistry=%s\n  _authToken = token\n' "$npm_ok" > "$d/.npmrc"
expect_fail npm-auth-after-good-lines "$d" "authentication key _authToken"

d="$(new_case npm-crlf-registry)"
printf 'registry=https://registry.example.test/\r\n' > "$d/.npmrc"
expect_fail npm-crlf-registry "$d" ".npmrc: registry"

# npm: accepted.
d="$(new_case npm-good)"
printf '# comment with registry=https://registry.example.test/\n; _authToken=x\nignore-scripts=true\nregistry=%s\n@acme:registry=%s\naudit=false\n' "$npm_ok" "$npm_ok" > "$d/.npmrc"
expect_pass npm-good "$d"

# NuGet: refused.
d="$(new_case nuget-third-party-source)"
nuget_file "$d/nuget.config" '    <clear />
    <add key="evil" value="https://nuget.example.test/v3/index.json" />'
expect_fail nuget-third-party-source "$d" "nuget.config: package source https://nuget.example.test/v3/index.json"

d="$(new_case nuget-extra-source-next-to-nuget-org)"
nuget_file "$d/NuGet.Config" '    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
    <add key="local" value="/tmp/feed" />'
expect_fail nuget-extra-source-next-to-nuget-org "$d" "NuGet.Config: package source /tmp/feed"

d="$(new_case nuget-source-on-several-lines)"
printf '<configuration>\n<packageSources>\n<clear />\n<add\n  key="x"\n  value="https://nuget.example.test/index.json"\n/>\n</packageSources>\n</configuration>\n' > "$d/nuget.config"
expect_fail nuget-source-on-several-lines "$d" "package source https://nuget.example.test/index.json"

d="$(new_case nuget-single-quotes-and-case)"
printf "<configuration><PackageSources><Clear/><add key='x' VALUE='https://nuget.example.test/index.json'/></PackageSources></configuration>\n" > "$d/nuget.config"
expect_fail nuget-single-quotes-and-case "$d" "package source https://nuget.example.test/index.json"

d="$(new_case nuget-no-clear)"
nuget_file "$d/nuget.config" "    <add key=\"nuget.org\" value=\"$nuget_ok\" />"
expect_fail nuget-no-clear "$d" "nuget.config: packageSources has no <clear />"

d="$(new_case nuget-empty-sources-no-clear)"
printf '<configuration>\n  <packageSources />\n</configuration>\n' > "$d/nuget.config"
expect_fail nuget-empty-sources-no-clear "$d" "packageSources has no <clear />"

d="$(new_case nuget-credentials)"
printf '<configuration>\n  <packageSources>\n    <clear />\n    <add key="nuget.org" value="%s" />\n  </packageSources>\n  <packageSourceCredentials>\n    <nuget.org>\n      <add key="Username" value="u" />\n    </nuget.org>\n  </packageSourceCredentials>\n</configuration>\n' "$nuget_ok" > "$d/nuget.config"
expect_fail nuget-credentials "$d" "nuget.config: packageSourceCredentials section"

d="$(new_case nuget-empty-credentials)"
printf '<configuration>\n  <packageSources>\n    <clear />\n    <add key="nuget.org" value="%s" />\n  </packageSources>\n  <packageSourceCredentials />\n</configuration>\n' "$nuget_ok" > "$d/nuget.config"
expect_fail nuget-empty-credentials "$d" "packageSourceCredentials section"

d="$(new_case nuget-unterminated-comment)"
printf '<configuration>\n  <!-- never closed\n  <packageSources><clear /><add key="x" value="%s" /></packageSources>\n</configuration>\n' "$nuget_ok" > "$d/nuget.config"
expect_fail nuget-unterminated-comment "$d" "unterminated XML comment"

# NuGet: accepted.
d="$(new_case nuget-good)"
printf '<?xml version="1.0" encoding="utf-8"?>\n<!-- <add key="x" value="https://nuget.example.test/" /> -->\n<configuration>\n  <!-- a > b -->\n  <packageSources>\n    <clear />\n    <!-- <packageSourceCredentials /> -->\n    <add key="nuget.org" value="%s" protocolVersion="3" />\n  </packageSources>\n</configuration>\n' "$nuget_ok" > "$d/nuget.config"
expect_pass nuget-good "$d"

# Mixed: one bad file among good ones is enough, and every file is reported.
d="$(new_case both-bad)"
printf 'registry=https://registry.example.test/\n' > "$d/.npmrc"
nuget_file "$d/nuget.config" "    <add key=\"nuget.org\" value=\"$nuget_ok\" />"
expect_fail both-bad "$d" ".npmrc: registry"
expect_fail both-bad-nuget "$d" "nuget.config: packageSources has no <clear />"

# Nothing to scan passes.
d="$(new_case empty-root)"
expect_pass empty-root "$d"

if [ "$failures" -gt 0 ]; then
  printf '%s of %s S29 case(s) failed.\n' "$failures" "$cases" >&2
  exit 1
fi
printf 'All %s S29 case(s) passed.\n' "$cases"
