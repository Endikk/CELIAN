#!/bin/sh
# Minimal HTTP/1.0 client for the BENCH-012 client pod (busybox sh and nc).
# The benchmark may not call curl or wget: every request of the identity
# provider tests goes through this script, inside the cluster.
#
# Usage: http.sh METHOD HOST:PORT HOST_HEADER PATH [HEADER...]
#   The request body, for any method but GET, is read from stdin.
#   Prints the raw response (status line, headers, empty line, body).
# HTTP/1.0 with "Connection: close" keeps the response unchunked, and the
# server closes the connection when it is done. busybox nc gives no clean way
# to send a request and then wait for the server to close, so `nc -e` runs a
# small program on the connected socket: it writes the request, then copies
# the response to a file until the server closes. `timeout` bounds a request
# that gets no answer. The request and response files live in a private
# temporary directory of the pod, removed on exit.
set -eu
method=$1
hostport=$2
host_header=$3
path=$4
shift 4
host=${hostport%:*}
port=${hostport##*:}
body=""
if [ "$method" != GET ]; then body=$(cat); fi
dir=$(mktemp -d)
trap 'rm -f "$dir/req" "$dir/resp" "$dir/run"; rmdir "$dir"' EXIT
{
  printf '%s %s HTTP/1.0\r\nHost: %s\r\nConnection: close\r\nAccept: application/json\r\n' \
    "$method" "$path" "$host_header"
  for header in "$@"; do printf '%s\r\n' "$header"; done
  if [ "$method" != GET ]; then printf 'Content-Length: %s\r\n' "${#body}"; fi
  printf '\r\n%s' "$body"
} >"$dir/req"
printf '#!/bin/sh\ncat "%s/req"\ncat >"%s/resp"\n' "$dir" "$dir" >"$dir/run"
chmod 700 "$dir/run"
status=0
timeout 8 nc -w 8 "$host" "$port" -e "$dir/run" || status=$?
if [ -f "$dir/resp" ]; then cat "$dir/resp"; fi
exit "$status"
