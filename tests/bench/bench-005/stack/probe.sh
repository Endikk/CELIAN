#!/bin/sh
# BENCH-005 probe, run by busybox inside the environment under test (a pod in
# kind, a container with Compose and Aspire). Every half second it prints one
# line with what the API and the front answer, and whether Postgres and the
# cache accept a connection. The benchmark reads these lines from the logs.
# Postgres and the cache are checked until they first answer, then latched.
pg=no
cache=
while true; do
  a=$(wget -qO- -T 2 "$API_URL" 2>/dev/null | head -n 1)
  f=$(wget -qO- -T 2 "$FRONT_URL" 2>/dev/null | grep -o 'marker-[0-9a-z-]*' | head -n 1)
  if [ "$pg" != ok ] && nc -w 1 "$PG_HOST" "$PG_PORT" </dev/null >/dev/null 2>&1; then
    pg=ok
  fi
  if [ -z "$cache" ]; then
    cache=$(printf 'PING\r\n' | nc -w 1 "$CACHE_HOST" "$CACHE_PORT" 2>/dev/null | tr -d '\r' | head -n 1)
  fi
  echo "probe api=[$a] front=[$f] pg=[$pg] cache=[$cache]"
  sleep 0.5
done
