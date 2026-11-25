#!/usr/bin/env bash
# control: P06
# carries: FR-016; ADR-011, conditions 7 and 11; contracts/task-cli.md
#
# The mirror does not start without the configuration of the project: with
# local/mirror/zot/config.json missing, local/scripts/mirror.sh refuses in
# one sentence that names the file, before any call that changes the engine
# (ADR-011, condition 7). With it, the configuration is mounted read-only at
# the path that serve reads, the command of the image. The image
# comes by tag and digest from ghcr.io/project-zot/zot, the network kind
# exists first (the cluster creates it), and the container or the volume
# named after the mirror is removed or reused only when it is the
# project's: label and image checked (ADR-011, condition 11; E22 plays it
# on kind). Simulated docker only (lib/mirror-harness.sh).
set -uo pipefail
# shellcheck disable=SC1091 # lib/mirror-harness.sh is checked on its own
. "$(dirname "${BASH_SOURCE[0]}")/lib/mirror-harness.sh"

config_mount="--mount type=bind,src=$PROJECT/local/mirror/zot/config.json,dst=/etc/zot/config.json,readonly"

run_mirror_case "configuration missing: refused, nothing created" \
  --without local/mirror/zot/config.json -- up "$MIRROR_TEST_IMAGE"
expect_refused
expect_output "local/mirror/zot/config.json"
expect_output "Nothing was created"
expect_no_change

run_mirror_case "configuration present: mounted read-only where serve reads it" \
  -- up "$MIRROR_TEST_IMAGE"
expect_ok
for part in $config_mount serve /etc/zot/config.json; do
  expect_run_has "$part"
done
expect_output "Mirror: container saas-b2b-mirror"

run_mirror_case "no image given: refused" -- up
expect_refused
expect_output "ghcr.io/project-zot/zot"
expect_no_change

run_mirror_case "image by tag only: refused" -- up "ghcr.io/project-zot/zot:v2.1.23"
expect_refused
expect_output "by tag and digest"
expect_no_change

run_mirror_case "image of another repository: refused" \
  -- up "docker.io/library/registry:3@sha256:9d3de83ac2099e6f4843045b4c9b65b7e8baf40f92d28f54906dee9d4d390fd7"
expect_refused
expect_output "ghcr.io/project-zot/zot"
expect_no_change

run_mirror_case "network kind missing: refused, nothing created" FAKE_KIND_NETWORK=absent \
  -- up "$MIRROR_TEST_IMAGE"
expect_refused
expect_output "network kind"
expect_no_change

run_mirror_case "old mirror of the project: removed, then started again" FAKE_MIRROR_CONTAINER=ours \
  -- up "$MIRROR_TEST_IMAGE"
expect_ok
expect_called "docker container rm --force saas-b2b-mirror"
if ! awk '/^docker container rm /{r=NR} /^docker run /{s=NR} END{exit !(r && s && r < s)}' "$CALLS"; then
  fail_case "the old container must be removed before the new one starts"
fi

run_mirror_case "container of the same name with another label: refused, left alone" \
  FAKE_MIRROR_CONTAINER=foreign-label -- up "$MIRROR_TEST_IMAGE"
expect_refused
expect_output "is not the mirror of this project"
expect_no_change

run_mirror_case "container of the same name with another image: refused, left alone" \
  FAKE_MIRROR_CONTAINER=foreign-image -- up "$MIRROR_TEST_IMAGE"
expect_refused
expect_output "is not the mirror of this project"
expect_no_change

run_mirror_case "volume of the same name without the label: refused" FAKE_MIRROR_VOLUME=foreign \
  -- up "$MIRROR_TEST_IMAGE"
expect_refused
expect_output "volume saas-b2b-mirror"
expect_no_change

run_mirror_case "volume of the project: reused, not created again" FAKE_MIRROR_VOLUME=ours \
  -- up "$MIRROR_TEST_IMAGE"
expect_ok
if grep -q '^docker volume create ' "$CALLS"; then
  fail_case "the volume of the project must be reused"
fi

run_mirror_case "mirror that stops at start: refused with its last log lines" FAKE_MIRROR_HEALTH=exited \
  -- up "$MIRROR_TEST_IMAGE"
expect_refused
expect_output "simulated log line of the mirror"

run_mirror_case "unknown command: refused" -- start "$MIRROR_TEST_IMAGE"
expect_refused
expect_no_change

finish
