#!/usr/bin/env bash
# control: P04
# carries: FR-001; ADR-004, condition 1; research RS-20; spec 001, edge cases
#
# A host port already taken on 127.0.0.1 stops task up before anything is
# created, and the refusal names the port. The ports are given by the test;
# the real ones arrive with step 7 (T059). The TCP probe is replaced by a
# stub (lib/harness.sh, --taken), the other binaries are simulated.
set -uo pipefail
# shellcheck disable=SC1091 # lib/harness.sh is checked on its own
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

run_case "both ports free" --taken "" -- 18080 18443
expect_ok
expect_output "Preflight checks passed"

run_case "second port taken" --taken "18443" -- 18080 18443
expect_refused
expect_output "host port 18443 is already in use on 127.0.0.1"
expect_no_output "18080"
expect_output "Nothing was created"

run_case "both ports taken" --taken "18080 18443" -- 18080 18443
expect_refused
expect_output "host ports 18080 18443 are already in use on 127.0.0.1"

run_case "ports checked last, after the versions" --taken "18443" FAKE_KIND_VERSION=0.32.0 -- 18080 18443
expect_refused
expect_output "kind 0.32.0 found"
expect_no_output "18443"

run_case "ports checked after the memory" --taken "18443" FAKE_DOCKER_MEM_TOTAL=$((1900 * MIB)) -- 18443
expect_refused
expect_output "148 MiB more"
expect_no_output "18443"

run_case "not a number" --taken "" -- 18080 80x
expect_refused
expect_output "\"80x\" is not a host port"
expect_not_called docker

run_case "port 0" --taken "" -- 0
expect_refused
expect_output "\"0\" is not a host port"

run_case "port above 65535" --taken "" -- 65536
expect_refused
expect_output "\"65536\" is not a host port"

finish
