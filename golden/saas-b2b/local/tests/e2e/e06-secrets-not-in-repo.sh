#!/usr/bin/env bash
# control: E06
# carries: FR-004; ADR-007, condition 1; principle IX; research RS-10
#
# The passwords that task up drew, and the private key of gateway-tls, are
# nowhere in the repository: neither in the working tree of the Git
# repository that holds the golden repo, nor in its history (git log --all
# -p), in clear or in base64. For the key, the lines of its PEM body and the
# base64 that the Secret stores. The values never
# leave the memory of the test: grep reads them as patterns from a pipe that
# printf, a builtin of bash, writes, and prints only the names of the files
# that match. On a runner, the checkout holds the history it fetched.
set -uo pipefail
# shellcheck disable=SC1091 # lib/e2e.sh is checked on its own
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/e2e.sh"

must_succeed up || e2e_finish

values=""
for secret in $E2E_PASSWORD_SECRETS; do
  if ! value="$(secret_value "$secret" password)" || [ -z "$value" ]; then
    fail "the Secret $secret has no readable password after task up"
    continue
  fi
  values="$values$value"$'\n'
  values="$values$(printf '%s' "$value" | base64 | tr -d '\n')"$'\n'
done

# The private key of gateway-tls (research RS-10), searched the same way and
# never printed: each line of the body of its PEM, which is what a copy of
# the key in a file would hold, and the base64 of the whole value as the
# Secret stores it, which is what a manifest would hold. The label lines and
# the lines shorter than TLS_LINE_MIN characters are left out: too short to
# tell a key from any other text.
readonly TLS_LINE_MIN=16
if ! key="$(secret_value "$E2E_TLS_SECRET" tls.key)" || [ -z "$key" ]; then
  fail "the Secret $E2E_TLS_SECRET has no readable key tls.key after task up"
else
  while IFS= read -r line; do
    case "$line" in
      -----*) continue ;;
    esac
    [ "${#line}" -ge "$TLS_LINE_MIN" ] && values="$values$line"$'\n'
  done < <(printf '%s\n' "$key")
  stored="$(kube_e2e --namespace "$E2E_APP_NAMESPACE" get secret "$E2E_TLS_SECRET" --output 'jsonpath={.data.tls\.key}')"
  [ -n "$stored" ] && values="$values$stored"$'\n'
fi
[ -n "$values" ] || e2e_finish

if ! top="$(git -C "$E2E_ROOT" rev-parse --show-toplevel 2>/dev/null)"; then
  fail "$E2E_ROOT is not in a Git repository: E06 cannot read the history"
  e2e_finish
fi

# The working tree, .git aside.
found="$(grep -r -l -F -f <(printf '%s' "$values") --exclude-dir=.git -- "$top" 2>/dev/null || true)"
if [ -n "$found" ]; then
  fail "a password of task up is in the working tree: $(printf '%s' "$found" | tr '\n' ' ')"
fi

# The history, every reference.
commits="$(git -C "$top" rev-list --all --count 2>/dev/null || printf '?')"
hits="$(git -C "$top" log --all -p --no-color --no-ext-diff 2>/dev/null | grep -c -F -f <(printf '%s' "$values") || true)"
if [ "$hits" != 0 ]; then
  fail "a password of task up is in the history of the repository ($hits line(s))"
fi
printf 'note: %s value(s), clear and base64, searched in %s and %s commit(s) of its history.\n' \
  "$(printf '%s' "$values" | grep -c .)" "$top" "$commits"

e2e_finish
