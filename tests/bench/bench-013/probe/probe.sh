#!/bin/sh
# BENCH-013 probe, run by a Job inside the cluster (busybox sh, as an
# unprivileged user). Access checks first (M8), then one mail sent over SMTP
# and read back through the HTTP API of the option (M5). It prints key=value
# lines only: never a credential, never a response body.
# Environment: MODE, SMTP_HOST, SMTP_PORT, HTTP_HOST, HTTP_PORT, API_PATH from
# the ConfigMap probe-target; UI_USER and UI_PASS from the Secret mail-ui-auth.
set -u

if [ "${MODE:-}" = none ]; then
  echo "mode=none"
  exit 0
fi

subject="celian-bench-013-$(hostname)"
auth=$(printf '%s:%s' "$UI_USER" "$UI_PASS" | base64 | tr -d '\n')

# One HTTP/1.0 GET of the API through nc. $1: an extra header line with its
# CRLF written as \r\n, or an empty string. The request goes through a FIFO
# whose writer stays open for a few seconds: nc must not half-close the
# connection right after the request, since smtp4dev (Kestrel) then sends no
# answer (smoke test 3). nc returns as soon as the server closes the
# connection, and the writer is stopped.
fifo=/tmp/probe-request
mkfifo "$fifo"
request() {
  {
    printf 'GET %s HTTP/1.0\r\nHost: %s\r\n%bConnection: close\r\n\r\n' \
      "$API_PATH" "$HTTP_HOST" "$1"
    sleep 5
  } >"$fifo" &
  feeder=$!
  nc -w 5 "$HTTP_HOST" "$HTTP_PORT" <"$fifo"
  kill "$feeder" 2>/dev/null
  wait "$feeder" 2>/dev/null
}
status_of() { request "$1" | head -n 1 | cut -d' ' -f2; }
uptime_s() { cut -d' ' -f1 /proc/uptime; }

echo "mode=$MODE"
echo "noauth_status=$(status_of '')"
echo "auth_status=$(status_of "Authorization: Basic $auth\r\n")"

t0=$(uptime_s)
if printf 'Subject: %s\r\nFrom: bench@example.invalid\r\nTo: dev@example.invalid\r\n\r\nBENCH-013 probe\r\n' "$subject" |
  sendmail -S "$SMTP_HOST:$SMTP_PORT" -f bench@example.invalid dev@example.invalid; then
  echo "smtp_send=ok"
else
  echo "smtp_send=failed"
  exit 1
fi

found=no
while :; do
  if request "Authorization: Basic $auth\r\n" | grep -q "$subject"; then
    found=yes
    break
  fi
  if awk -v a="$t0" -v b="$(uptime_s)" 'BEGIN { exit !(b - a > 60) }'; then break; fi
  sleep 0.1 2>/dev/null || sleep 1
done
t1=$(uptime_s)
echo "found=$found"
echo "send_to_api_s=$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.2f", b - a }')"
[ "$found" = yes ]
