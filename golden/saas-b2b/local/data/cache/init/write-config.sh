#!/bin/sh
# The configuration of the cache of the local layer (ADR-015, conditions 4,
# 10, 13 and 15; research RS-11), written by the init container config of
# local/data/cache/deployment.yaml, which runs it with the sh of the image,
# BusyBox, from the read-only ConfigMap cache-config-writer.
#
# The password of cache-auth goes from its file to sha256sum through the
# standard input, and only its SHA-256 reaches cache.conf, in the ACL line
# of the user default (src/acl.c of Valkey 9.1.4: # then 64 lower-case hex
# characters). The password is never in an argument, a variable or a file
# other than the one of the Secret. It is checked first, as
# local/scripts/secrets.sh draws it: one line of 32 alphanumeric characters
# at least, which also refuses the known values of the example files
# (ADR-015, condition 19).
#
# The ACL line gives the user default everything but @admin and
# @scripting, then refuses each command that Memorystore blocks and @admin
# misses (research RS-11). Persistence is off, maxmemory is 64mb with
# allkeys-lru, and the three protected commands stay off. cache.conf lives
# in a volume in memory, readable by the UID of the server alone.
set -eu
umask 077

secret=/run/secrets/cache-auth/password
conf=/etc/cache/cache.conf

fail() {
  printf 'write-config.sh: %s The cache does not start.\n' "$1" >&2
  exit 1
}

[ -s "$secret" ] || fail "the Secret cache-auth has no file password, or it is empty."
[ "$(grep -c '' "$secret")" -eq 1 ] || fail "the password of cache-auth holds more than one line."
grep -Eqx '[A-Za-z0-9]{32,}' "$secret" || fail "the password of cache-auth is not 32 alphanumeric characters at least."

hash="$(tr -d '\r\n' <"$secret" | sha256sum | cut -d ' ' -f 1)"
case "$hash" in
  *[!0-9a-f]* | '') fail "sha256sum gave no SHA-256 of the password." ;;
esac
[ "${#hash}" -eq 64 ] || fail "sha256sum gave no SHA-256 of the password."

{
  echo 'save ""'
  echo 'appendonly no'
  echo 'protected-mode yes'
  echo 'maxmemory 64mb'
  echo 'maxmemory-policy allkeys-lru'
  echo 'enable-protected-configs no'
  echo 'enable-debug-command no'
  echo 'enable-module-command no'
  printf 'user default on #%s ~* &* +@all -@admin -@scripting -acl -migrate -move -restore-asking -swapdb -xsetid\n' "$hash"
} >"$conf"
echo "write-config.sh: cache.conf written, with the SHA-256 of the password of cache-auth."
