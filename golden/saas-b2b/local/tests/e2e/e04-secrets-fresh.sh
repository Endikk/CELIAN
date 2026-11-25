#!/usr/bin/env bash
# control: E04
# carries: FR-004, FR-005; SC-004; ADR-007, condition 1; ADR-012, condition 10; ADR-015, condition 19
#
# Two new environments share no password: task down, task up, read the
# passwords of db-auth, db-superuser and cache-auth; task down, task up, read them
# again. Each password is 32 characters at least and none of the known
# values (root, admin, postgres, password, changeme, mysecretpassword,
# foobared, password123, the empty value); the three passwords of one
# environment differ; no password of the first environment comes back in the
# second. username is fixed by construction and stays out of the comparison
# (ADR-012, condition 10). The values stay in the memory of the test: no
# message prints one. The mirror volume is kept between both, so the second
# start reads the images from it.
set -uo pipefail
# shellcheck disable=SC1091 # lib/e2e.sh is checked on its own
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/e2e.sh"

# read_passwords: sets PASSWORDS to the passwords of the Secrets of
# E2E_PASSWORD_SECRETS, one per line, in that order; checks each against the rules,
# and fails the test on a break, in this shell.
read_passwords() {
  local secret value known
  PASSWORDS=""
  for secret in $E2E_PASSWORD_SECRETS; do
    if ! value="$(secret_value "$secret" password)"; then
      fail "the Secret $secret has no readable key password after task up"
      continue
    fi
    if [ "${#value}" -lt "$E2E_MIN_PASSWORD_LENGTH" ]; then
      fail "the password of $secret is ${#value} characters long, $E2E_MIN_PASSWORD_LENGTH at least expected"
    fi
    for known in $E2E_KNOWN_VALUES; do
      [ "$value" = "$known" ] && fail "the password of $secret is a known value"
    done
    PASSWORDS="$PASSWORDS$value"$'\n'
  done
}

# distinct_count VALUES: the number of distinct lines of VALUES.
distinct_count() {
  printf '%s' "$1" | LC_ALL=C sort -u | grep -c . || true
}

must_succeed down || e2e_finish
must_succeed up || e2e_finish
read_passwords
first="$PASSWORDS"
if [ "$(distinct_count "$first")" -ne 3 ]; then
  fail "the three passwords of the first environment are not three distinct values"
fi

must_succeed down || e2e_finish
must_succeed up || e2e_finish
read_passwords
second="$PASSWORDS"
if [ "$(distinct_count "$second")" -ne 3 ]; then
  fail "the three passwords of the second environment are not three distinct values"
fi

common="$(LC_ALL=C comm -12 <(printf '%s' "$first" | LC_ALL=C sort -u) <(printf '%s' "$second" | LC_ALL=C sort -u) | grep -c . || true)"
if [ "$common" -ne 0 ]; then
  fail "$common password(s) of the first environment come back in the second"
fi
printf 'note: two new environments, %s and %s distinct passwords, none shared.\n' \
  "$(distinct_count "$first")" "$(distinct_count "$second")"

e2e_finish
