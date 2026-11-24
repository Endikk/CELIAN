#!/usr/bin/env bash
# control: P03
# carries: FR-006; ADR-004, condition 6; research RS-08
#
# The memory that the engine declares picks the profile: from 2560 MiB the
# standard, from 2048 MiB the lite, announced, and below that a refusal
# that gives the memory missing (VM of 2.5 and 2.0 GiB, research RS-08).
# PROFILE forces a profile under the same checks. Until step 12 the standard
# profile is recognised, then refused with a clear message. Simulated
# binaries only (lib/harness.sh).
set -uo pipefail
# shellcheck disable=SC1091 # lib/harness.sh is checked on its own
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

run_case "4 GiB: standard, recognised then refused until step 12" FAKE_DOCKER_MEM_TOTAL=$((4 * GIB))
expect_refused
expect_output "Profile: standard"
expect_output "the engine declares 4096 MiB"
expect_output "not delivered yet"
expect_output "step 12"
expect_output "PROFILE=lite task up"

run_case "2560 MiB exactly: standard" FAKE_DOCKER_MEM_TOTAL=$((2560 * MIB))
expect_refused
expect_output "Profile: standard"
expect_output "not delivered yet"

run_case "2304 MiB: lite, announced" FAKE_DOCKER_MEM_TOTAL=$((2304 * MIB))
expect_ok
expect_output "Profile: lite"
expect_output "the engine declares 2304 MiB"
expect_output "the standard profile needs 2560 MiB"

run_case "2048 MiB exactly: lite" FAKE_DOCKER_MEM_TOTAL=$((2048 * MIB))
expect_ok
expect_output "Profile: lite"

run_case "1900 MiB: refused, 148 MiB missing" FAKE_DOCKER_MEM_TOTAL=$((1900 * MIB))
expect_refused
expect_output "the container engine declares 1900 MiB"
expect_output "the lite profile needs 2048 MiB"
expect_output "148 MiB more"
expect_output "README.md"

run_case "one byte under 2048 MiB: refused, 1 MiB missing" FAKE_DOCKER_MEM_TOTAL=$((2048 * MIB - 1))
expect_refused
expect_output "1 MiB more"

run_case "PROFILE=lite with 4 GiB: lite" PROFILE=lite FAKE_DOCKER_MEM_TOTAL=$((4 * GIB))
expect_ok
expect_output "Profile: lite, forced by PROFILE"

run_case "PROFILE=lite with 1900 MiB: refused" PROFILE=lite FAKE_DOCKER_MEM_TOTAL=$((1900 * MIB))
expect_refused
expect_output "the lite profile needs 2048 MiB"
expect_output "148 MiB more"

run_case "PROFILE=standard with 2304 MiB: refused, 256 MiB missing" \
  PROFILE=standard FAKE_DOCKER_MEM_TOTAL=$((2304 * MIB))
expect_refused
expect_output "the standard profile needs 2560 MiB"
expect_output "256 MiB more"

run_case "PROFILE=standard with 4 GiB: recognised then refused until step 12" \
  PROFILE=standard FAKE_DOCKER_MEM_TOTAL=$((4 * GIB))
expect_refused
expect_output "Profile: standard, forced by PROFILE"
expect_output "step 12"

run_case "PROFILE empty: chosen by memory" PROFILE= FAKE_DOCKER_MEM_TOTAL=$((2304 * MIB))
expect_ok
expect_output "Profile: lite"

run_case "PROFILE=full: refused before any call" PROFILE=full
expect_refused
expect_output "PROFILE=full is not a profile"
expect_output "PROFILE=lite or PROFILE=standard"
expect_not_called docker

finish
