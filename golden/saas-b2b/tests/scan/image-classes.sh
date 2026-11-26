#!/usr/bin/env bash
# Prints the classes of the images written in a policy file (spec 001, FR-021,
# FR-022; decision of the DSI of 2026-11-25), one "<class>|<entry>" line per
# entry, and "<class>|" for a class that holds none. The file is the one of
# security/scan-policy.yaml: under scan_policy, an image_classes block whose
# keys are the classes and whose entries are "- <repository>" lines. Read by
# S25 and S26, which judge the classes; the decision itself reads them
# through conftest (policy/scan_decision.rego), not through this script.
#
# Usage: tests/scan/image-classes.sh <file>
set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
  echo "usage: tests/scan/image-classes.sh <policy file>" >&2
  exit 1
fi

out="$(awk '
  {
    line = $0
    sub(/[ \t]+#.*$/, "", line)
    if (line ~ /^[ \t]*(#.*)?$/) next
    match(line, /^ */)
    indent = RLENGTH
    text = substr(line, indent + 1)
    gsub(/["\047]/, "", text)
    if (in_block && indent <= 2) in_block = 0
    if (!in_block) {
      if (indent == 2 && text ~ /^image_classes:[ \t]*$/) { in_block = 1; found = 1 }
      next
    }
    if (indent == 4 && text ~ /^-[ \t]/) {
      sub(/^-[ \t]+/, "", text)
      print "?|" text
    } else if (indent == 4 && text ~ /:/) {
      class = text
      sub(/:.*$/, "", class)
      value = text
      sub(/^[^:]*:[ \t]*/, "", value)
      if (value == "" || value == "[]") print class "|"
      else print class "|" value
    } else if (indent > 4 && text ~ /^-[ \t]/) {
      sub(/^-[ \t]+/, "", text)
      sub(/[ \t]+$/, "", text)
      print class "|" text
    } else {
      print "?|" text
    }
  }
  END { if (!found) exit 3 }
' "$1")" || {
  echo "no image_classes block under scan_policy (two-space indent), where the scan reads the class of each image." >&2
  exit 1
}
printf '%s\n' "$out"
