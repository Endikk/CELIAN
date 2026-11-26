#!/usr/bin/env bash
# control: S13
# carries: FR-008, FR-016; ADR-011, conditions 1, 2, 5, 7, 9, 10 and 13
#
# The mirror and the registry hosts of the node keep the conditions of
# ADR-011:
# - local/policy/mirror_config.rego reads the zot configuration, each
#   hosts.toml and the kind configuration: pull alone, sync alone, no
#   credential, the files derived from the one list local/mirror/registries;
# - local/scripts/mirror.sh, run against a simulated docker
#   (local/tests/preflight/lib/mirror-harness.sh), starts the mirror on the
#   network kind with no published port, its storage in a named volume of
#   the engine and never in the project tree, the configuration read-only,
#   the image by digest, the default restart policy.
set -uo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
CDPATH='' cd -- "$root" || exit 2

registries="local/mirror/registries"
local_env="local/scripts/lib/local-env.sh"

if ! command -v conftest >/dev/null 2>&1; then
  echo "conftest is not installed: run tests/tools/install.sh <dir>, then put <dir> on PATH." >&2
  exit 1
fi
for file in "$registries" "$local_env" local/mirror/zot/config.json local/kind/cluster.yaml; do
  if [ ! -f "$file" ]; then
    echo "$file is missing: the mirror of task up is not written yet (spec 001, T046 to T049)." >&2
    exit 1
  fi
done

# The name of the mirror container, which the hosts.toml files name.
# shellcheck disable=SC1090 # local-env.sh is checked on its own
mirror_name="$(HOME=/nonexistent bash -c '. "$1" && printf "%s" "$MIRROR_CONTAINER"' s13 "$local_env")"
if [ -z "$mirror_name" ]; then
  echo "$local_env does not set MIRROR_CONTAINER." >&2
  exit 1
fi

# local/mirror/registries: one registry per line, "<namespace> <upstream>",
# comments and blank lines aside. Each line is checked before it enters the
# data of the policy, so the JSON written below needs no escaping.
work="$(mktemp -d)" || exit 2
trap 'rm -rf "${work:?}"' EXIT
entries=""
line_number=0
while IFS= read -r line || [ -n "$line" ]; do
  line_number=$((line_number + 1))
  case "$line" in
    "" | "#"*) continue ;;
  esac
  if ! [[ $line =~ ^([a-z0-9][a-z0-9.-]*(:[0-9]+)?)\ (https://[A-Za-z0-9.-]+(:[0-9]+)?)$ ]]; then
    echo "$registries, line $line_number: \"$line\" is not \"<registry> https://<upstream>\"." >&2
    exit 1
  fi
  entries="$entries${entries:+,}{\"namespace\":\"${BASH_REMATCH[1]}\",\"upstream\":\"${BASH_REMATCH[3]}\"}"
done <"$registries"
printf '{"registries":[%s],"mirror_name":"%s"}\n' "$entries" "$mirror_name" >"$work/mirror.json"

hosts_files=()
for file in local/mirror/certs.d/*/hosts.toml; do
  [ -f "$file" ] && hosts_files+=("$file")
done

conftest verify --no-color --policy local/policy --namespace mirror_config || exit 1
conftest test --no-color --combine --policy local/policy --namespace mirror_config \
  --data "$work/mirror.json" local/mirror/zot/config.json local/kind/cluster.yaml \
  ${hosts_files[@]+"${hosts_files[@]}"} || exit 1

rm -rf "${work:?}"
trap - EXIT

# The launch, against the simulated docker.
# shellcheck disable=SC1091 # mirror-harness.sh is checked on its own
. local/tests/preflight/lib/mirror-harness.sh

run_mirror_case "launch of the mirror" -- up "$MIRROR_TEST_IMAGE"
expect_ok
for part in --detach "--network kind" "--name $mirror_name" "--label invalid.saas-b2b.role=registry-mirror" \
  "--mount type=volume,src=saas-b2b-mirror,dst=/home/nonroot" "$MIRROR_TEST_IMAGE serve /etc/zot/config.json"; do
  expect_run_has "$part"
done
# The hardening: no capability, no privilege gained, a read-only root
# filesystem (ADR-011, condition 7). E03 reads the same three back from the
# engine.
for part in "--cap-drop ALL" "--security-opt no-new-privileges=true" --read-only; do
  expect_run_has "$part"
done
# One user, the nonroot UID of the distroless image, written as UID:GID (ADR-011,
# condition 6; E23 reads it back from the engine); no other form of the option
# (--user=X, -u X, -uX), no extra privilege, whatever the form: --privileged[=true],
# --cap-add; and one --security-opt only.
expect_run_has "--user 65532:65532"
if [ "$(run_line | grep -o -- '--user' | wc -l | tr -d ' ')" != 1 ]; then
  fail_case "the mirror has one --user, 65532:65532: $(run_line)"
fi
expect_run_lacks "--user=*"
expect_run_lacks "-u"
expect_run_lacks "-u*"
expect_run_lacks "--privileged*"
expect_run_lacks "--cap-add*"
if [ "$(run_line | grep -o -- '--security-opt' | wc -l | tr -d ' ')" != 1 ]; then
  fail_case "the mirror has one --security-opt, no-new-privileges: $(run_line)"
fi
# No published port, no other network, no restart policy, no bind mount but
# the configuration, read-only, and no anonymous volume.
expect_run_lacks "-p"
expect_run_lacks "-P"
expect_run_lacks "--publish*"
expect_run_lacks "--network=*"
expect_run_lacks "--net"
expect_run_lacks "--net=*"
expect_run_lacks "--restart*"
expect_run_lacks "-v"
expect_run_lacks "--volume*"
if [ "$(run_line | grep -o -- '--network' | wc -l | tr -d ' ')" != 1 ]; then
  fail_case "the mirror joins one network, kind: $(run_line)"
fi
mounts="$(run_line | grep -o -- '--mount [^ ]*' || true)"
if [ "$(printf '%s\n' "$mounts" | grep -c 'type=bind')" != 1 ] ||
  ! printf '%s\n' "$mounts" | grep -q "type=bind,src=$PROJECT/local/mirror/zot/config.json,dst=/etc/zot/config.json,readonly\$"; then
  fail_case "the only bind mount is the configuration, read-only: $mounts"
fi

# Task up checks the mirror (image, configuration, container, volume) before
# it creates the cluster: a foreign container must not cost the 30 to 75 s of
# a cluster creation (contracts/task-cli.md, checks before creation).
# shellcheck disable=SC2034 # CASE is read by fail_case of the harness
CASE="task up checks the mirror before the cluster"
CASES=$((CASES + 1))
check_line="$(grep -n "^ *- bash local/scripts/mirror.sh check " local/tasks/local.yml | head -1 | cut -d: -f1)"
cluster_line="$(grep -n "^ *- bash local/scripts/\(steps.sh run cluster -- bash local/scripts/\)\{0,1\}cluster.sh up" local/tasks/local.yml | head -1 | cut -d: -f1)"
if [ -z "$check_line" ] || [ -z "$cluster_line" ] || [ "$check_line" -ge "$cluster_line" ]; then
  fail_case "local/tasks/local.yml must call mirror.sh check before cluster.sh up (check at line ${check_line:-none}, cluster at line ${cluster_line:-none})"
fi

finish
