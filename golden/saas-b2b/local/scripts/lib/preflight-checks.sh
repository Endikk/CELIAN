# shellcheck shell=bash
# Preflight checks of `task up` (spec 001, contracts/task-cli.md), run before
# anything is created, in the order of the contract:
#   1. docker reaches a local engine through a unix socket, and the engine
#      answers within DOCKER_TIMEOUT_SECONDS;
#   2. versions: kind exactly, kubectl within one minor of the cluster,
#      Docker Engine 28.0.0 or later on Linux;
#   3. the memory that the engine declares picks the profile;
#   4. the host ports are free on 127.0.0.1.
# The inputs, PROFILE and the ports, are validated first, before any call.
#
# It only reads: "docker context inspect" (the local store of contexts),
# "docker info", "kind version", "kubectl version --client" (which reads no
# kubeconfig), "uname -s", platform.yaml, and a TCP connect to each port.
# It creates nothing and touches no kubeconfig. The source of each command
# and of each output format is in research RS-08 of spec 001.
#
# Library of local/scripts/preflight.sh, which sources it, then runs main
# with no condition: run or sourced, the script checks. The preflight tests
# source this file too, to replace port_in_use
# (local/tests/preflight/lib/harness.sh). Sourcing it sets the shell options
# and the locale of the checks, so that both run them the same way.

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  printf '%s is a library: run bash local/scripts/preflight.sh instead.\n' "$0" >&2
  exit 2
fi

set -euo pipefail
# The C locale: the character classes of printable hold ASCII only, and the
# system message that port_in_use reads, "Connection refused", is not
# translated.
export LC_ALL=C

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
# Seconds that each docker call gets to answer. docker info answers in
# 0.03 s on the measurement machine; the docker CLI bounds only its first
# ping, at 2 s, then waits on the engine with no limit (research RS-08).
# 10 s leaves a slow engine in a virtual machine time to answer, and reports
# a stuck one without a long wait.
readonly DOCKER_TIMEOUT_SECONDS=10
# Every host port of the cluster is published on this address (ADR-004,
# condition 1).
readonly LOOPBACK="127.0.0.1"
# Longest value from outside that a message shows (printable).
readonly PRINTABLE_MAX=200
readonly README_REF='README.md, section "Prérequis de task up"'
readonly MIB=1048576

preflight_lib_dir="${BASH_SOURCE[0]}"
case "$preflight_lib_dir" in
  */*) preflight_lib_dir="${preflight_lib_dir%/*}" ;;
  *) preflight_lib_dir="." ;;
esac
# CDPATH='': with a CDPATH exported, cd would also print the directory, and
# the path would come out on two lines.
PLATFORM_FILE="$(CDPATH='' cd -- "$preflight_lib_dir/../../.." && pwd)/platform.yaml"
readonly PLATFORM_FILE

# Set by read_engine, cluster_minor, choose_profile, scan_output and
# port_in_use.
ENGINE_VERSION=""
ENGINE_MEMORY=0
CLUSTER_MAJOR=""
CLUSTER_MINOR=""
PROFILE_RETAINED=""
SCAN_MESSAGE=""
PORT_PROBE_MESSAGE=""

refuse() {
  printf 'task up: %s Nothing was created.\n' "$1" >&2
  exit 1
}

# printable VALUE: prints VALUE with every character that is not printable
# in the C locale replaced by "?" (the control characters, line feed
# included, and every byte above 0x7E), cut after PRINTABLE_MAX characters.
# Applied to every value from outside before it is shown, so that it can
# neither send a terminal sequence nor start a line of its own in a log.
printable() {
  local value="${1//[![:print:]]/?}"
  if [ "${#value}" -gt "$PRINTABLE_MAX" ]; then
    value="${value:0:$PRINTABLE_MAX}..."
  fi
  printf '%s' "$value"
}

# run_bounded SECONDS COMMAND...: runs COMMAND and returns its status, or 124
# when it has failed after SECONDS or more: a watchdog stops it once SECONDS
# have passed, with TERM, then KILL a second later. Bash 3.2 has no timeout
# and macOS has no timeout(1). The watchdog polls COMMAND in the background
# with kill -0 every second, so that a command that ends at once returns at
# once. Only COMMAND is stopped: a child that it left running would keep its
# output open.
run_bounded() {
  local limit="$1" pid watchdog status=0 start="$SECONDS"
  shift
  "$@" &
  pid=$!
  watch_command "$pid" "$limit" >/dev/null 2>&1 &
  watchdog=$!
  wait "$pid" || status=$?
  kill "$watchdog" 2>/dev/null || :
  wait "$watchdog" 2>/dev/null || :
  if [ "$status" -ne 0 ] && [ $((SECONDS - start)) -ge "$limit" ]; then
    return 124
  fi
  return "$status"
}

# watch_command PID SECONDS: the watchdog of run_bounded.
watch_command() {
  local waited=0
  while kill -0 "$1" 2>/dev/null; do
    if [ "$waited" -ge "$2" ]; then
      kill -TERM "$1" 2>/dev/null || return 0
      sleep 1
      kill -KILL "$1" 2>/dev/null || :
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
}

validate_inputs() {
  local port
  case "${PROFILE:-}" in
    "" | lite | standard) ;;
    *) refuse "PROFILE=$(printable "$PROFILE") is not a profile: use PROFILE=lite or PROFILE=standard, or leave PROFILE unset." ;;
  esac
  for port in "$@"; do
    case "$port" in
      "" | *[!0-9]*) refuse "\"$(printable "$port")\" is not a host port: give numbers from 1 to 65535." ;;
    esac
    if [ "${#port}" -gt 5 ] || [ "$((10#$port))" -lt 1 ] || [ "$((10#$port))" -gt 65535 ]; then
      refuse "\"$port\" is not a host port: give numbers from 1 to 65535."
    fi
  done
}

# scan_output OUTPUT PATTERN: finds the first line of OUTPUT that matches
# PATTERN, leaves its groups in BASH_REMATCH and succeeds, or fails.
# SCAN_MESSAGE gets the first other line that holds a letter: the message of
# the command, without the empty values that docker renders on an error.
scan_output() {
  local rest="$1" pattern="$2" line
  SCAN_MESSAGE=""
  while [ -n "$rest" ]; do
    line="${rest%%$'\n'*}"
    if [ "$line" = "$rest" ]; then
      rest=""
    else
      rest="${rest#*$'\n'}"
    fi
    if [[ $line =~ $pattern ]]; then
      return 0
    fi
    if [ -z "$SCAN_MESSAGE" ]; then
      case "$line" in
        *[A-Za-z]*) SCAN_MESSAGE="$line" ;;
      esac
    fi
  done
  return 1
}

# The engine that docker reaches is where kind creates the cluster: kind
# runs the docker command (research RS-08). Without a name, docker context
# inspect inspects the current context: --context, then DOCKER_HOST (the
# context "default"), then DOCKER_CONTEXT, then the configuration. Only a
# unix socket is accepted; a tcp or ssh host, or any other, can be another
# machine, whose memory, version and ports the checks below would read.
check_docker_context() {
  local out status=0 matched=no name="" host=""
  local pattern='^([A-Za-z0-9][A-Za-z0-9_.+-]*) ([A-Za-z][A-Za-z0-9+.-]*://[^[:space:]]*)$'
  out="$(run_bounded "$DOCKER_TIMEOUT_SECONDS" \
    docker context inspect --format '{{.Name}} {{.Endpoints.docker.Host}}' 2>&1)" || status=$?
  if [ "$status" -eq 124 ]; then
    refuse "docker gave no answer to \"docker context inspect\" within $DOCKER_TIMEOUT_SECONDS s. Check the docker command, then run task up again ($README_REF)."
  fi
  if scan_output "$out" "$pattern"; then
    matched=yes
    name="${BASH_REMATCH[1]}"
    host="${BASH_REMATCH[2]}"
  fi
  if [ "$status" -ne 0 ] || [ "$matched" != yes ]; then
    refuse "the current docker context cannot be read with \"docker context inspect\": $(printable "${SCAN_MESSAGE:-no message}"). Check DOCKER_CONTEXT and the output of docker context ls, then run task up again ($README_REF)."
  fi
  name="$(printable "$name")"
  host="$(printable "$host")"
  case "$host" in
    unix://?*)
      printf 'Container engine: docker context %s, local socket %s.\n' "$name" "$host"
      return 0
      ;;
  esac
  if [ -n "${DOCKER_HOST:-}" ]; then
    refuse "DOCKER_HOST points docker at $host (context $name), not at a local unix socket: kind would create the cluster on that engine. Run unset DOCKER_HOST, then task up again ($README_REF)."
  fi
  if [ -n "${DOCKER_CONTEXT:-}" ]; then
    refuse "DOCKER_CONTEXT selects the docker context $name, which points at $host, not at a local unix socket: kind would create the cluster on that engine. Run unset DOCKER_CONTEXT, then task up again ($README_REF)."
  fi
  refuse "the docker context $name points at $host, not at a local unix socket: kind would create the cluster on that engine. Run docker context use default, or switch to another local context, then task up again ($README_REF)."
}

read_engine() {
  local out status=0 pattern='^([0-9]+\.[0-9]+[^[:space:]]*) ([1-9][0-9]*)$'
  if ! command -v docker >/dev/null 2>&1; then
    refuse "no container engine found: the docker command is not on PATH. Install a container engine that provides it ($README_REF)."
  fi
  check_docker_context
  # A connection failure exits non-zero; an error of the engine itself is
  # printed and exits 0 with empty values (research RS-08): both refused.
  out="$(run_bounded "$DOCKER_TIMEOUT_SECONDS" \
    docker info --format '{{.ServerVersion}} {{.MemTotal}}' 2>&1)" || status=$?
  if [ "$status" -eq 124 ]; then
    refuse "the container engine gave no answer to \"docker info\" within $DOCKER_TIMEOUT_SECONDS s. Restart the engine, then run task up again ($README_REF)."
  fi
  if scan_output "$out" "$pattern" && [ "$status" -eq 0 ]; then
    ENGINE_VERSION="${BASH_REMATCH[1]}"
    ENGINE_MEMORY="${BASH_REMATCH[2]}"
    return 0
  fi
  refuse "the container engine does not answer to \"docker info\": $(printable "${SCAN_MESSAGE:-no message}"). Start the engine, then run task up again ($README_REF)."
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
    refuse "kind $(printable "$found") found, $KIND_VERSION expected: install kind $KIND_VERSION ($README_REF)."
  fi
}

# Sets CLUSTER_MAJOR and CLUSTER_MINOR from kubernetes_minor in platform.yaml.
cluster_minor() {
  local line value="" pattern='^([0-9]+)\.([0-9]+)$'
  if [ ! -f "$PLATFORM_FILE" ]; then
    refuse "$(printable "$PLATFORM_FILE") is missing: it holds the Kubernetes minor of the cluster."
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
    refuse "kubernetes_minor cannot be read in $(printable "$PLATFORM_FILE")."
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
    refuse "kubectl $(printable "$found") found, $expected expected, within one minor of the cluster's $major.$minor: install a kubectl in that range ($README_REF)."
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
    refuse "Docker Engine $(printable "$ENGINE_VERSION") found, $DOCKER_ENGINE_LINUX_MIN or later expected on Linux, where older versions let the local network reach unpublished container ports (ADR-011): update Docker Engine ($README_REF)."
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

# port_in_use PORT: returns 0 when something accepts a TCP connection on
# PORT, 1 when the connection is refused, the one sign that the port is
# free, and 2 on any other outcome, which tells neither (a bash built
# without /dev/tcp, a filter on the loopback); PORT_PROBE_MESSAGE then gets
# the end of the message of bash. Bash opens /dev/tcp/<host>/<port> itself
# (research RS-08): no other tool is needed, and a listener of any user is
# seen.
port_in_use() {
  local message
  if message="$( (: <>"/dev/tcp/$LOOPBACK/$1") 2>&1)"; then
    return 0
  fi
  case "$message" in
    *"Connection refused"*) return 1 ;;
  esac
  message="${message##*$'\n'}"
  PORT_PROBE_MESSAGE="${message##*: }"
  return 2
}

# The result of port_in_use is read through "|| status=$?", never through
# "if": an "if" would take 2, a probe that tells neither, for a free port.
check_ports() {
  local port status taken="" unknown="" message=""
  for port in "$@"; do
    status=0
    PORT_PROBE_MESSAGE=""
    port_in_use "$port" || status=$?
    case "$status" in
      0) taken="$taken $port" ;;
      1) ;;
      *)
        unknown="$unknown $port"
        [ -n "$message" ] || message="${PORT_PROBE_MESSAGE:-no message}"
        ;;
    esac
  done
  taken="${taken# }"
  unknown="${unknown# }"
  case "$taken" in
    "") ;;
    *" "*) refuse "host ports $taken are already in use on $LOOPBACK: free them, then run task up again." ;;
    *) refuse "host port $taken is already in use on $LOOPBACK: free it, then run task up again." ;;
  esac
  case "$unknown" in
    "") return 0 ;;
    *" "*) unknown="host ports $unknown" ;;
    *) unknown="host port $unknown" ;;
  esac
  refuse "$unknown cannot be checked on $LOOPBACK: the probe of bash got neither a connection nor a refusal ($(printable "$message")). Check that this bash supports /dev/tcp and that nothing filters $LOOPBACK, then run task up again ($README_REF)."
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
