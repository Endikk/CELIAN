#!/usr/bin/env bash
# control: P02
# carries: FR-001; spec 001, edge cases; contracts/task-cli.md
#
# Container engine missing or stopped: task up says so in one sentence that
# names the engine expected, creates nothing, and checks it first, before
# any version (contracts/task-cli.md, "dans cet ordre"). Simulated binaries
# only (lib/harness.sh).
set -uo pipefail
# shellcheck disable=SC1091 # lib/harness.sh is checked on its own
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

run_case "engine running"
expect_ok
expect_called "docker info --format {{.ServerVersion}} {{.MemTotal}}"

run_case "no docker command" --without docker
expect_refused
expect_output "no container engine found: the docker command is not on PATH"
expect_output "README.md"
expect_output "Nothing was created"

run_case "engine stopped" FAKE_DOCKER_STATE=stopped
expect_refused
expect_output "the container engine does not answer"
expect_output "failed to connect to the docker API"
expect_output "Start the engine"
expect_output "Nothing was created"

run_case "engine answering with an error, docker exits 0" FAKE_DOCKER_STATE=server-error
expect_refused
expect_output "the container engine does not answer"
expect_output "simulated server error"

run_case "engine checked before the versions" FAKE_DOCKER_STATE=stopped \
  FAKE_KIND_VERSION=0.32.0 FAKE_KUBECTL_GIT_VERSION=v1.34.9
expect_refused
expect_output "the container engine does not answer"
expect_no_output "kind 0.32.0"
expect_not_called kind
expect_not_called kubectl

run_case "engine missing and kind missing" --without docker --without kind
expect_refused
expect_output "no container engine found"
expect_no_output "kind is not installed"

finish
