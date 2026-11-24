#!/usr/bin/env bash
# control: P01
# carries: FR-001; ADR-004, condition 2; ADR-006, condition 5; ADR-011, condition 3
#
# task up refuses, before creating anything, a kind other than 0.33.0, a
# kubectl outside the minors 1.35 to 1.37 (one minor around the 1.36 of
# platform.yaml), and a Docker Engine older than 28.0.0 on Linux. The
# refusal gives the version found, shown without control characters, the
# version expected and the README. Simulated binaries only (lib/harness.sh).
set -uo pipefail
# shellcheck disable=SC1091 # lib/harness.sh is checked on its own
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

run_case "supported versions on macOS"
expect_ok
expect_called "kind version --quiet"
expect_called "kubectl version --client --output=json"
expect_output "Preflight checks passed"

run_case "kind 0.32.0" FAKE_KIND_VERSION=0.32.0
expect_refused
expect_output "kind 0.32.0 found, 0.33.0 expected"
expect_output "README.md"

run_case "kind 0.33.1" FAKE_KIND_VERSION=0.33.1
expect_refused
expect_output "kind 0.33.1 found, 0.33.0 expected"

run_case "kind version unreadable" FAKE_KIND_VERSION=
expect_refused
expect_output "0.33.0 expected"
expect_output "README.md"

run_case "kind missing" --without kind
expect_refused
expect_output "kind is not installed"
expect_output "0.33.0"

run_case "kubectl 1.34" FAKE_KUBECTL_GIT_VERSION=v1.34.9
expect_refused
expect_output "kubectl 1.34.9 found, 1.35 to 1.37 expected"
expect_output "README.md"

run_case "kubectl 1.38" FAKE_KUBECTL_GIT_VERSION=v1.38.0
expect_refused
expect_output "kubectl 1.38.0 found, 1.35 to 1.37 expected"

run_case "kubectl 1.35, lowest minor of the range" FAKE_KUBECTL_GIT_VERSION=v1.35.0
expect_ok

run_case "kubectl 1.36, minor of the cluster" FAKE_KUBECTL_GIT_VERSION=v1.36.4
expect_ok

run_case "kubectl 2.36" FAKE_KUBECTL_GIT_VERSION=v2.36.0
expect_refused
expect_output "kubectl 2.36.0 found, 1.35 to 1.37 expected"

run_case "kubectl version unreadable" FAKE_KUBECTL_GIT_VERSION=unknown
expect_refused
expect_output "1.35 to 1.37 expected"

run_case "kubectl missing" --without kubectl
expect_refused
expect_output "kubectl is not installed"
expect_output "1.35 to 1.37"

run_case "Docker Engine 27.5.1 on Linux" FAKE_UNAME_S=Linux FAKE_DOCKER_SERVER_VERSION=27.5.1
expect_refused
expect_output "Docker Engine 27.5.1 found, 28.0.0 or later expected on Linux"
expect_output "README.md"

run_case "Docker Engine of a distribution package, older than 28.0.0, on Linux" \
  FAKE_UNAME_S=Linux FAKE_DOCKER_SERVER_VERSION=26.1.5+dfsg1
expect_refused
expect_output "Docker Engine 26.1.5+dfsg1 found, 28.0.0 or later expected on Linux"

run_case "Docker Engine 28.0.0 on Linux" FAKE_UNAME_S=Linux FAKE_DOCKER_SERVER_VERSION=28.0.0
expect_ok

run_case "Docker Engine 29.8.2 on Linux" FAKE_UNAME_S=Linux FAKE_DOCKER_SERVER_VERSION=29.8.2
expect_ok

run_case "engine 27.5.1 on macOS, where the rule does not apply" FAKE_DOCKER_SERVER_VERSION=27.5.1
expect_ok

# A version read from a tool is shown without its control characters: ESC
# and the byte 0x9B (CSI of the C1 controls) each become "?".
run_case "kind version with terminal sequences, shown printable" FAKE_KIND_VERSION=$'0.33.0\033[2K\x9b1A'
expect_refused
expect_no_control_characters
expect_output "kind 0.33.0?[2K?1A found, 0.33.0 expected"

run_case "Docker Engine version with a terminal sequence, on Linux, shown printable" \
  FAKE_UNAME_S=Linux FAKE_DOCKER_SERVER_VERSION=$'27.5.1\033]0;title\007'
expect_refused
expect_no_control_characters
expect_output "Docker Engine 27.5.1?]0;title? found"

run_case "kind checked before kubectl" FAKE_KIND_VERSION=0.32.0 FAKE_KUBECTL_GIT_VERSION=v1.34.9
expect_refused
expect_output "kind 0.32.0 found"
expect_no_output "kubectl 1.34.9"

finish
