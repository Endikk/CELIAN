# shellcheck shell=bash
# The role of db-auth and its database, created at the first start of an
# empty volume (ADR-012, conditions 2 and 8; research RS-04 and RS-12).
#
# docker-entrypoint.sh of the official image sources this file, which the
# ConfigMap postgres-init mounts without the execute bit, while its
# temporary server listens on the Unix socket alone. Its function
# docker_process_sql runs psql as the superuser of db-superuser, with
# PGPASSWORD set: local connections ask for scram-sha-256 too.
#
# The role logs in, owns the database app and has no other attribute:
# neither superuser nor CREATEDB nor CREATEROLE. Its password goes from the
# file of db-auth to psql through a pipe: never in an argument nor in an
# environment variable, and the session sets log_min_error_statement to
# PANIC, so that a failing statement, which would carry it, never reaches
# the log. The values are checked first: a name of lower-case letters,
# digits and underscores, and a password of 32 alphanumeric characters at
# least, as local/scripts/secrets.sh draws it.

readonly APP_ROLE_SECRET_DIR="/run/secrets/db-auth"
readonly APP_ROLE_DATABASE="app"

app_role_name="$(cat "$APP_ROLE_SECRET_DIR/username")"
if ! [[ $app_role_name =~ ^[a-z_][a-z0-9_]{0,62}$ ]]; then
  printf '10-app-role.sh: the username of db-auth is not a role name of lower-case letters, digits and underscores; the database is not initialized.\n' >&2
  exit 1
fi
if ! grep -Eqx '[A-Za-z0-9]{32,}' "$APP_ROLE_SECRET_DIR/password"; then
  printf '10-app-role.sh: the password of db-auth is not 32 alphanumeric characters at least; the database is not initialized.\n' >&2
  exit 1
fi

{
  printf 'SET log_min_error_statement TO panic;\n'
  printf "CREATE ROLE %s WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD '" "$app_role_name"
  cat "$APP_ROLE_SECRET_DIR/password"
  printf "';\n"
  printf 'CREATE DATABASE %s OWNER %s;\n' "$APP_ROLE_DATABASE" "$app_role_name"
} | docker_process_sql --dbname postgres
printf '10-app-role.sh: role %s and database %s created.\n' "$app_role_name" "$APP_ROLE_DATABASE"
