#!/usr/bin/env bash
# control: E04
# carries: FR-004, FR-005; SC-004; ADR-007, condition 1; ADR-012, condition 10; ADR-015, condition 19; research RS-10
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
#
# gateway-tls holds a key and a certificate, no password (research RS-10;
# contracts/secrets.md): the 32-character rule does not apply to it. In each
# environment its tls.key is a PEM private key, its tls.crt a PEM
# certificate, and the key is the key of the certificate; between the two
# environments neither the key nor the certificate comes back. Only their
# SHA-256 fingerprints are kept and compared; none is printed.
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

# read_tls: sets TLS_SUMS to the SHA-256 fingerprints of tls.crt and tls.key
# of gateway-tls, one per line, and fails the test when the Secret is not a
# PEM certificate with the PEM private key that belongs to it.
read_tls() {
  local crt_head key_head
  TLS_SUMS=""
  crt_head="$(secret_value "$E2E_TLS_SECRET" tls.crt 2>/dev/null | head -n 1)"
  key_head="$(secret_value "$E2E_TLS_SECRET" tls.key 2>/dev/null | head -n 1)"
  if [ "$crt_head" != "-----BEGIN CERTIFICATE-----" ]; then
    fail "the key tls.crt of $E2E_TLS_SECRET is not a PEM certificate after task up"
  fi
  # A pattern, not the label itself: the hook detect-private-key of the
  # repository refuses a file that holds the label of a private key.
  if ! [[ $key_head =~ ^-----BEGIN\ ([A-Z]+\ )?PRIVATE\ KEY-----$ ]]; then
    fail "the key tls.key of $E2E_TLS_SECRET is not a PEM private key after task up"
  fi
  tls_pair_matches || fail "the key tls.key of $E2E_TLS_SECRET is not the key of the certificate tls.crt"
  TLS_SUMS="$(secret_value "$E2E_TLS_SECRET" tls.crt 2>/dev/null | sha256_stdin)"$'\n'
  TLS_SUMS="$TLS_SUMS$(secret_value "$E2E_TLS_SECRET" tls.key 2>/dev/null | sha256_stdin)"$'\n'
}

# distinct_count VALUES: the number of distinct lines of VALUES.
distinct_count() {
  printf '%s' "$1" | LC_ALL=C sort -u | grep -c . || true
}

must_succeed down || e2e_finish
must_succeed up || e2e_finish
read_passwords
read_tls
first_tls="$TLS_SUMS"
first="$PASSWORDS"
if [ "$(distinct_count "$first")" -ne 3 ]; then
  fail "the three passwords of the first environment are not three distinct values"
fi

must_succeed down || e2e_finish
must_succeed up || e2e_finish
read_passwords
read_tls
second_tls="$TLS_SUMS"
second="$PASSWORDS"
if [ "$(distinct_count "$second")" -ne 3 ]; then
  fail "the three passwords of the second environment are not three distinct values"
fi

common="$(LC_ALL=C comm -12 <(printf '%s' "$first" | LC_ALL=C sort -u) <(printf '%s' "$second" | LC_ALL=C sort -u) | grep -c . || true)"
if [ "$common" -ne 0 ]; then
  fail "$common password(s) of the first environment come back in the second"
fi
tls_common="$(LC_ALL=C comm -12 <(printf '%s' "$first_tls" | LC_ALL=C sort -u) <(printf '%s' "$second_tls" | LC_ALL=C sort -u) | grep -c . || true)"
if [ "$tls_common" -ne 0 ]; then
  fail "the key or the certificate of $E2E_TLS_SECRET of the first environment comes back in the second ($tls_common value(s))"
fi
printf 'note: two new environments, %s and %s distinct passwords, none shared; the key and the certificate of %s differ.\n' \
  "$(distinct_count "$first")" "$(distinct_count "$second")" "$E2E_TLS_SECRET"

e2e_finish
