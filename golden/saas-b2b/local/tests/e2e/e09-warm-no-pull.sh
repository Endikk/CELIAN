#!/usr/bin/env bash
# control: E09
# carries: FR-008, FR-016; ADR-011, condition 4; research RS-07
#
# T1 (spec 001, T085): on a cluster that is kept, task up pulls no image.
# The node reports each pull as an event of reason Pulling, from the
# kubelet. The test notes the events of that reason, with their counts, runs
# task up on the environment that stands, and compares: no new event, and no
# higher count. The images of the API and the front come from kind load,
# never from a registry: a pod of the application that asked for a pull would
# show here, and so would an image that task up pulled again.
set -uo pipefail
# shellcheck disable=SC1091 # lib/e2e.sh is checked on its own
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/e2e.sh"

must_succeed up || e2e_finish

# pulls: one line per event of reason Pulling in the cluster: its UID, its
# count, the object, and the image in the message.
pulls() {
  kube_e2e get events --all-namespaces --field-selector reason=Pulling \
    --output 'jsonpath={range .items[*]}{.metadata.uid} {.count} {.involvedObject.namespace}/{.involvedObject.name} {.message}{"\n"}{end}' |
    LC_ALL=C sort
}

before="$(pulls)"
printf 'note: %s pull event(s) so far, from the first start.\n' "$(printf '%s\n' "$before" | grep -c .)"

must_succeed up || e2e_finish

after="$(pulls)"
if [ "$after" != "$before" ]; then
  fail "task up on a kept cluster pulled an image: the events of reason Pulling changed. New or changed lines:"
  printf '%s\n' "$after" | LC_ALL=C grep -v -x -F -f <(printf '%s\n' "$before") | sed 's/^/    /'
fi

e2e_finish
