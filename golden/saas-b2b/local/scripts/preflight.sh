#!/usr/bin/env bash
# Preflight checks of `task up` (spec 001, contracts/task-cli.md), run before
# anything is created, in the order of the contract:
#   1. the container engine answers;
#   2. versions: kind exactly, kubectl within one minor of the cluster,
#      Docker Engine 28.0.0 or later on Linux;
#   3. the memory that the engine declares picks the profile;
#   4. the host ports are free on 127.0.0.1.
# The inputs, PROFILE and the ports, are validated first, before any call.
#
# It only reads: "docker info", "kind version", "kubectl version --client"
# (which reads no kubeconfig), "uname -s", platform.yaml, and a TCP connect
# to each port. It creates nothing and touches no kubeconfig. The source of
# each command and of each output format is in research RS-08 of spec 001.
#
# Usage: bash local/scripts/preflight.sh [PORT...]
#   PORT     a host port that the cluster will publish on 127.0.0.1; the
#            tasks pass the real ones from step 7 (T059)
#   PROFILE  environment, optional: lite or standard forces the profile,
#            under the same memory checks
# Announces the profile retained. A refusal is one sentence that says what
# is missing and what to do, on stderr, with exit status 1.
set -euo pipefail

# ADR-004, condition 2: the exact version of kind. It moves with the node
# image of local/kind/cluster.yaml, in one PR (ADR-004, version rule, point 5).
readonly KIND_VERSION="0.33.0"
# kubectl is supported within one minor of the API server (ADR-006,
# condition 5; Kubernetes version skew policy). The minor of the cluster is
# kubernetes_minor in platform.yaml.
readonly KUBECTL_MINOR_SKEW=1
# ADR-011, condition 3: older engines let the local network reach container
# ports that are not published. On Linux only.
readonly DOCKER_ENGINE_LINUX_MIN="28.0.0"
# Starting thresholds of the profiles, in memory declared by the engine
# (research RS-08: VM of 2.0 GiB for lite, 2.5 GiB for the known part of
# standard). Recomputed on the first measure of the golden repo (T081).
readonly LITE_MIN_MIB=2048
readonly STANDARD_MIN_MIB=2560
# The standard profile arrives with step 12 of spec 001; until then it is
# recognised, then refused.
readonly STANDARD_DELIVERED="no"
# Every host port of the cluster is published on this address (ADR-004,
# condition 1).
readonly LOOPBACK="127.0.0.1"
readonly README_REF='README.md, section "Prérequis de task up"'
readonly MIB=1048576

here="${BASH_SOURCE[0]}"
case "$here" in
  */*) here="${here%/*}" ;;
  *) here="." ;;
esac
PLATFORM_FILE="$(cd "$here/../.." && pwd)/platform.yaml"
readonly PLATFORM_FILE

# Set by read_engine, cluster_minor and choose_profile.
ENGINE_VERSION=""
ENGINE_MEMORY=0
ENGINE_MESSAGE=""
CLUSTER_MAJOR=""
CLUSTER_MINOR=""
PROFILE_RETAINED=""

refuse() {
  printf 'task up: %s Nothing was created.\n' "$1" >&2
  exit 1
}

validate_inputs() {
  local port
  case "${PROFILE:-}" in
    "" | lite | standard) ;;
    *) refuse "PROFILE=$PROFILE is not a profile: use PROFILE=lite or PROFILE=standard, or leave PROFILE unset." ;;
  esac
  for port in "$@"; do
    case "$port" in
      "" | *[!0-9]*) refuse "\"$port\" is not a host port: give numbers from 1 to 65535." ;;
    esac
    if [ "${#port}" -gt 5 ] || [ "$((10#$port))" -lt 1 ] || [ "$((10#$port))" -gt 65535 ]; then
      refuse "\"$port\" is not a host port: give numbers from 1 to 65535."
    fi
  done
}

# parse_engine_output OUTPUT: sets ENGINE_VERSION and ENGINE_MEMORY from the
# line "<version> <bytes>" of OUTPUT and succeeds, or fails. ENGINE_MESSAGE
# gets the first line that holds a letter: the message of docker, without
# the zero values that it renders when the engine does not answer.
parse_engine_output() {
  local rest="$1" line pattern='^([0-9]+\.[0-9]+[^[:space:]]*) ([1-9][0-9]*)$'
  while [ -n "$rest" ]; do
    line="${rest%%$'\n'*}"
    if [ "$line" = "$rest" ]; then
      rest=""
    else
      rest="${rest#*$'\n'}"
    fi
    if [[ $line =~ $pattern ]]; then
      ENGINE_VERSION="${BASH_REMATCH[1]}"
      ENGINE_MEMORY="${BASH_REMATCH[2]}"
      return 0
    fi
    if [ -z "$ENGINE_MESSAGE" ]; then
      case "$line" in
        *[A-Za-z]*) ENGINE_MESSAGE="$line" ;;
      esac
    fi
  done
  return 1
}

read_engine() {
  local out status=0
  if ! command -v docker >/dev/null 2>&1; then
    refuse "no container engine found: the docker command is not on PATH. Install a container engine that provides it ($README_REF)."
  fi
  # A connection failure exits non-zero; an error of the engine itself is
  # printed and exits 0 with empty values (research RS-08): both refused.
  out="$(docker info --format '{{.ServerVersion}} {{.MemTotal}}' 2>&1)" || status=$?
  if parse_engine_output "$out" && [ "$status" -eq 0 ]; then
    return 0
  fi
  refuse "the container engine does not answer to \"docker info\": ${ENGINE_MESSAGE:-no message}. Start the engine, then run task up again ($README_REF)."
}

check_kind() {
  local found
  if ! command -v kind >/dev/null 2>&1; then
    refuse "kind is not installed: install kind $KIND_VERSION ($README_REF)."
  fi
  found="$(kind version --quiet 2>/dev/null)" || found=""
  found="${found%%$'\n'*}"
  if [ -z "$found" ]; then
    refuse "the version of kind cannot be read, $KIND_VERSION expected: install kind $KIND_VERSION ($README_REF)."
  fi
  if [ "$found" != "$KIND_VERSION" ]; then
    refuse "kind $found found, $KIND_VERSION expected: install kind $KIND_VERSION ($README_REF)."
  fi
}

# Sets CLUSTER_MAJOR and CLUSTER_MINOR from kubernetes_minor in platform.yaml.
cluster_minor() {
  local line value="" pattern='^([0-9]+)\.([0-9]+)$'
  if [ ! -f "$PLATFORM_FILE" ]; then
    refuse "$PLATFORM_FILE is missing: it holds the Kubernetes minor of the cluster."
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      kubernetes_minor:*)
        value="${line#kubernetes_minor:}"
        break
        ;;
    esac
  done <"$PLATFORM_FILE"
  value="${value//[\" ]/}"
  if ! [[ $value =~ $pattern ]]; then
    refuse "kubernetes_minor cannot be read in $PLATFORM_FILE."
  fi
  CLUSTER_MAJOR="${BASH_REMATCH[1]}"
  CLUSTER_MINOR="${BASH_REMATCH[2]}"
}

check_kubectl() {
  local major minor low high expected out found pattern='"gitVersion": *"v(([0-9]+)\.([0-9]+)\.[^"]*)"'
  cluster_minor
  major="$CLUSTER_MAJOR"
  minor="$((10#$CLUSTER_MINOR))"
  low=$((minor - KUBECTL_MINOR_SKEW))
  high=$((minor + KUBECTL_MINOR_SKEW))
  expected="$major.$low to $major.$high"
  if ! command -v kubectl >/dev/null 2>&1; then
    refuse "kubectl is not installed: install kubectl $expected, within one minor of the cluster's $major.$minor ($README_REF)."
  fi
  out="$(kubectl version --client --output=json 2>/dev/null)" || out=""
  if ! [[ $out =~ $pattern ]]; then
    refuse "the version of kubectl cannot be read, $expected expected: install kubectl $expected ($README_REF)."
  fi
  found="${BASH_REMATCH[1]}"
  if [ "${BASH_REMATCH[2]}" != "$major" ] ||
    [ "$((10#${BASH_REMATCH[3]}))" -lt "$low" ] || [ "$((10#${BASH_REMATCH[3]}))" -gt "$high" ]; then
    refuse "kubectl $found found, $expected expected, within one minor of the cluster's $major.$minor: install a kubectl in that range ($README_REF)."
  fi
}

# version_at_least FOUND MINIMUM: compares the leading X.Y.Z numbers, so that
# a suffix such as +dfsg1 does not count.
version_at_least() {
  local pattern='^([0-9]+)\.([0-9]+)\.?([0-9]*)' f1 f2 f3 m1 m2 m3
  [[ $1 =~ $pattern ]] || return 1
  f1=$((10#${BASH_REMATCH[1]})) f2=$((10#${BASH_REMATCH[2]})) f3=$((10#${BASH_REMATCH[3]:-0}))
  [[ $2 =~ $pattern ]] || return 1
  m1=$((10#${BASH_REMATCH[1]})) m2=$((10#${BASH_REMATCH[2]})) m3=$((10#${BASH_REMATCH[3]:-0}))
  if [ "$f1" -ne "$m1" ]; then
    [ "$f1" -gt "$m1" ]
    return
  fi
  if [ "$f2" -ne "$m2" ]; then
    [ "$f2" -gt "$m2" ]
    return
  fi
  [ "$f3" -ge "$m3" ]
}

check_engine_version() {
  if [ "$(uname -s)" != Linux ]; then
    return 0
  fi
  if ! version_at_least "$ENGINE_VERSION" "$DOCKER_ENGINE_LINUX_MIN"; then
    refuse "Docker Engine $ENGINE_VERSION found, $DOCKER_ENGINE_LINUX_MIN or later expected on Linux, where older versions let the local network reach unpublished container ports (ADR-011): update Docker Engine ($README_REF)."
  fi
}

# refuse_short_memory PROFILE NEEDED_MIB
refuse_short_memory() {
  local needed=$(($2 * MIB))
  refuse "the container engine declares $((ENGINE_MEMORY / MIB)) MiB of memory, the $1 profile needs $2 MiB: give the engine $(((needed - ENGINE_MEMORY + MIB - 1) / MIB)) MiB more, in the settings of its virtual machine on macOS ($README_REF)."
}

# Sets PROFILE_RETAINED and announces it on stdout.
choose_profile() {
  local declared=$((ENGINE_MEMORY / MIB)) reason
  case "${PROFILE:-}" in
    "")
      if [ "$ENGINE_MEMORY" -ge $((STANDARD_MIN_MIB * MIB)) ]; then
        PROFILE_RETAINED=standard
        reason="the engine declares $declared MiB, $STANDARD_MIN_MIB MiB needed"
      elif [ "$ENGINE_MEMORY" -ge $((LITE_MIN_MIB * MIB)) ]; then
        PROFILE_RETAINED=lite
        reason="the engine declares $declared MiB, $LITE_MIN_MIB MiB needed; the standard profile needs $STANDARD_MIN_MIB MiB"
      else
        refuse_short_memory lite "$LITE_MIN_MIB"
      fi
      printf 'Profile: %s: %s.\n' "$PROFILE_RETAINED" "$reason"
      ;;
    lite)
      [ "$ENGINE_MEMORY" -ge $((LITE_MIN_MIB * MIB)) ] || refuse_short_memory lite "$LITE_MIN_MIB"
      PROFILE_RETAINED=lite
      printf 'Profile: lite, forced by PROFILE: the engine declares %s MiB, %s MiB needed.\n' "$declared" "$LITE_MIN_MIB"
      ;;
    standard)
      [ "$ENGINE_MEMORY" -ge $((STANDARD_MIN_MIB * MIB)) ] || refuse_short_memory standard "$STANDARD_MIN_MIB"
      PROFILE_RETAINED=standard
      printf 'Profile: standard, forced by PROFILE: the engine declares %s MiB, %s MiB needed.\n' "$declared" "$STANDARD_MIN_MIB"
      ;;
  esac
  if [ "$PROFILE_RETAINED" = standard ] && [ "$STANDARD_DELIVERED" != yes ]; then
    refuse "the standard profile is not delivered yet: it arrives with step 12 of spec 001. Run PROFILE=lite task up meanwhile."
  fi
}

# Something accepts a TCP connection on the port: it is taken. Bash opens
# /dev/tcp/<host>/<port> itself (research RS-08); no other tool is needed,
# and a listener of any user is seen.
port_in_use() {
  (: <>"/dev/tcp/$LOOPBACK/$1") 2>/dev/null
}

check_ports() {
  local port taken=""
  for port in "$@"; do
    if port_in_use "$port"; then
      taken="$taken $port"
    fi
  done
  taken="${taken# }"
  case "$taken" in
    "") ;;
    *" "*) refuse "host ports $taken are already in use on $LOOPBACK: free them, then run task up again." ;;
    *) refuse "host port $taken is already in use on $LOOPBACK: free it, then run task up again." ;;
  esac
}

main() {
  validate_inputs "$@"
  read_engine
  check_kind
  check_kubectl
  check_engine_version
  choose_profile
  check_ports "$@"
  printf 'Preflight checks passed: profile %s.\n' "$PROFILE_RETAINED"
}

# Sourced by the preflight tests, which replace port_in_use: main runs only
# when the script is run.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
