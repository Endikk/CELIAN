#!/usr/bin/env bash
# Checks that Renovate finds each version pinned in tests/tools/install.sh
# (research RS-17). Every line that sets a <NAME>_VERSION variable holds its
# value in double quotes, right below the comment that the custom manager of
# renovate.json reads:
#   # renovate: datasource=github-releases depName=<owner>/<repo>
# Without that comment, Renovate skips the version without a word. Called by
# tests/static/s23-renovate.sh, and in CELIAN by
# scripts/renovate/check-renovate.sh. One awk program shared by both, so the
# two checks cannot drift apart.
#
# Usage: tests/tools/check-renovate-comments.sh <install.sh>
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: tests/tools/check-renovate-comments.sh <install.sh>" >&2
  exit 1
fi
if [ ! -f "$1" ]; then
  echo "check-renovate-comments.sh: $1 is missing." >&2
  exit 1
fi

awk '
  /^[A-Z0-9_]+_VERSION=/ {
    found++
    if (prev !~ /^# renovate: datasource=github-releases depName=[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/ ||
        $0 !~ /^[A-Z0-9_]+_VERSION="[^" ]+"$/) {
      printf "%s, line %d: %s\n", FILENAME, NR, $0
      bad++
    }
  }
  { prev = $0 }
  END {
    if (found == 0) {
      printf "%s: no line sets a <NAME>_VERSION variable, so Renovate updates nothing in it.\n", FILENAME
      exit 1
    }
    if (bad > 0) {
      print "Each <NAME>_VERSION=\"<version>\" line sits right below \"# renovate: datasource=github-releases depName=<owner>/<repo>\", or Renovate does not see it."
      exit 1
    }
  }
' "$1" >&2
