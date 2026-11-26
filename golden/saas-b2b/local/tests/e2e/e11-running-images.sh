#!/usr/bin/env bash
# control: E11
# carries: FR-008; ADR-004, condition 3; ADR-011, conditions 4 and 10; research RS-07
#
# The pods that run (spec 001, T085), on the environment that task up left:
# every container, init containers included, of the pods of the application
# (the namespace of the application, and envoy-gateway-system, which task up
# fills) names an image
# - from a registry of the single list local/mirror/registries, or from the
#   reserved host saas-b2b.invalid of the images that task up builds;
# - by digest, except under saas-b2b.invalid (research RS-07).
# The pods of kube-system and local-path-storage run what the node image
# carries: no registry is asked for them, and the list does not cover them.
# Pods of the application must exist: an empty list proves nothing.
set -uo pipefail
# shellcheck disable=SC1091 # lib/e2e.sh is checked on its own
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/e2e.sh"

must_succeed up || e2e_finish

registries="$(awk '!/^#/ && NF { print $1 }' "$E2E_ROOT/local/mirror/registries")"
[ -n "$registries" ] || {
  fail "local/mirror/registries lists no registry"
  e2e_finish
}

# registry_of REFERENCE: the registry of an image reference, as Docker reads
# it: the first element when it holds a dot or a colon, or is localhost;
# docker.io otherwise.
registry_of() {
  local first="${1%%/*}"
  case "$1" in
    */*)
      case "$first" in
        localhost | *.* | *:*) printf '%s' "$first" ;;
        *) printf 'docker.io' ;;
      esac
      ;;
    *) printf 'docker.io' ;;
  esac
}

digest_pattern='@sha256:[0-9a-f]{64}$'
checked=0
for namespace in "$E2E_APP_NAMESPACE" envoy-gateway-system; do
  images="$(kube_e2e --namespace "$namespace" get pods \
    --output 'jsonpath={range .items[*]}{range .spec.initContainers[*]}{.image}{"\n"}{end}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | grep . | LC_ALL=C sort -u)"
  if [ -z "$images" ]; then
    fail "no pod runs in $namespace"
    continue
  fi
  while IFS= read -r image; do
    checked=$((checked + 1))
    registry="$(registry_of "$image")"
    if [ "$registry" = "$E2E_BUILT_HOST" ]; then
      continue
    fi
    if ! printf '%s\n' "$registries" | grep -qxF "$registry"; then
      fail "$namespace: $image comes from $registry, which is not in local/mirror/registries"
    fi
    [[ $image =~ $digest_pattern ]] || fail "$namespace: $image names no digest"
  done <<<"$images"
done

# The API and the front are among the pods, under the reserved host.
built="$(kube_e2e --namespace "$E2E_APP_NAMESPACE" get pods \
  --output 'jsonpath={range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | grep -c "^$E2E_BUILT_HOST/")"
[ "$built" -ge 2 ] || fail "$built pod(s) of the application run an image under $E2E_BUILT_HOST, the API and the front expected"

printf 'note: %s image reference(s) of running pods checked.\n' "$checked"
e2e_finish
