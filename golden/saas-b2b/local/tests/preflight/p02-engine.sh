#!/usr/bin/env bash
# control: P02
# carries: FR-001; spec 001, edge cases; contracts/task-cli.md
#
# Container engine missing, stopped, remote or stuck: task up says so in one
# sentence that names the engine expected, creates nothing, and checks it
# first, before any version (contracts/task-cli.md, "dans cet ordre"). The
# docker context must reach a local engine through a unix socket, since kind
# creates the cluster wherever docker points (research RS-08); it is
# announced when accepted. docker gets a bounded time to answer. A message
# of the engine is shown without its control characters. Simulated binaries
# only (lib/harness.sh).
set -uo pipefail
# shellcheck disable=SC1091 # lib/harness.sh is checked on its own
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

context_call="docker context inspect --format {{.Name}} {{.Endpoints.docker.Host}}"
orbstack_socket="unix:///Users/dev/.orbstack/run/docker.sock"

run_case "engine running"
expect_ok
expect_called "$context_call"
expect_called "docker info --format {{.ServerVersion}} {{.MemTotal}}"
expect_output "Container engine: docker context default, local socket unix:///var/run/docker.sock."

run_case "context on a local unix socket, announced" \
  FAKE_DOCKER_CONTEXT=orbstack FAKE_DOCKER_CONTEXT_HOST="$orbstack_socket"
expect_ok
expect_output "Container engine: docker context orbstack, local socket $orbstack_socket."

run_case "DOCKER_HOST on a local unix socket" DOCKER_HOST=unix:///run/user/1000/docker.sock
expect_ok
expect_output "Container engine: docker context default, local socket unix:///run/user/1000/docker.sock."

run_case "context on tcp: refused before docker info" \
  FAKE_DOCKER_CONTEXT=build-server FAKE_DOCKER_CONTEXT_HOST=tcp://192.0.2.10:2376
expect_refused
expect_output "the docker context build-server points at tcp://192.0.2.10:2376, not at a local unix socket"
expect_output "docker context use default"
expect_output "Nothing was created"
expect_only_call docker "$context_call"
expect_not_called kind

run_case "context on ssh: refused" \
  FAKE_DOCKER_CONTEXT=remote FAKE_DOCKER_CONTEXT_HOST=ssh://deploy@192.0.2.10
expect_refused
expect_output "the docker context remote points at ssh://deploy@192.0.2.10, not at a local unix socket"
expect_output "docker context use default"
expect_only_call docker "$context_call"

run_case "DOCKER_HOST on ssh: refused, over a local context" DOCKER_HOST=ssh://deploy@192.0.2.10 \
  FAKE_DOCKER_CONTEXT=orbstack FAKE_DOCKER_CONTEXT_HOST="$orbstack_socket"
expect_refused
expect_output "DOCKER_HOST points docker at ssh://deploy@192.0.2.10 (context default), not at a local unix socket"
expect_output "unset DOCKER_HOST"
expect_only_call docker "$context_call"

run_case "DOCKER_HOST on tcp: refused" DOCKER_HOST=tcp://192.0.2.10:2375
expect_refused
expect_output "DOCKER_HOST points docker at tcp://192.0.2.10:2375 (context default)"
expect_output "unset DOCKER_HOST"
expect_only_call docker "$context_call"

run_case "DOCKER_CONTEXT on a remote context: refused" \
  DOCKER_CONTEXT=remote FAKE_DOCKER_CONTEXT_HOST=ssh://deploy@192.0.2.10
expect_refused
expect_output "DOCKER_CONTEXT selects the docker context remote, which points at ssh://deploy@192.0.2.10"
expect_output "unset DOCKER_CONTEXT"
expect_only_call docker "$context_call"

run_case "current context that cannot be read" FAKE_DOCKER_CONTEXT=gone FAKE_DOCKER_CONTEXT_STATE=missing
expect_refused
expect_output "the current docker context cannot be read"
expect_output "context \"gone\": context not found"
expect_only_call docker "$context_call"

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

# ESC, BEL, CR and the byte 0x9B (CSI of the C1 controls) each become "?".
run_case "engine message with terminal sequences, shown printable" FAKE_DOCKER_STATE=server-error \
  FAKE_DOCKER_MESSAGE=$'Error response from daemon: \033]0;title\007 red \033[31m cr \r csi \x9b2J end'
expect_refused
expect_no_control_characters
expect_output "Error response from daemon: ?]0;title? red ?[31m cr ? csi ?2J end"

hang_start=$SECONDS
run_case "engine that never answers: stopped after 10 s" FAKE_DOCKER_STATE=hang
hang_seconds=$((SECONDS - hang_start))
expect_refused
expect_output "the container engine gave no answer to \"docker info\" within 10 s"
expect_output "Nothing was created"
expect_not_called kind
if [ "$hang_seconds" -lt 10 ] || [ "$hang_seconds" -ge 20 ]; then
  fail_case "expected a refusal after 10 to 20 s, got one after $hang_seconds s"
fi

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

# A task that sources preflight.sh instead of running it still runs the
# checks: no guard lets it end in success without them.
run_case "preflight.sh sourced instead of run: the checks still run" --sourced FAKE_DOCKER_STATE=stopped
expect_refused
expect_output "the container engine does not answer"

finish
