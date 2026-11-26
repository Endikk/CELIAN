#!/usr/bin/env bash
# control: S18
# carries: FR-018; ADR-004, conditions 5, 6 and 8; ADR-006, condition 5; ADR-011, conditions 3 and 12
#
# The README of the golden repo keeps what it promises. It is read against
# the files that hold the facts, so that a version, a threshold, a port or a
# task cannot change in one place and stay old in the other:
# - the table of tools gives, for Docker Engine, kind, kubectl, Task and Git,
#   a version, a licence, the date it was read and a source; the free engine
#   comes first (R-26), in the table and in the text;
# - the versions are those of local/scripts/lib/preflight-checks.sh (kind,
#   Docker Engine on Linux, the memory of each profile), of platform.yaml
#   (the minor of kubectl) and of tests/tools/install.sh (Task); the address
#   is the HTTP port of local/tasks/local.yml;
# - the install procedure of kind lists a SHA-256 per platform, equal to the
#   sums of catalog/kubernetes-cluster.yaml when the golden repo sits in
#   CELIAN (ADR-004, condition 5); a standalone copy has no catalog, and the
#   sums are then only checked for their shape;
# - the section named by the refusals of task up exists, and the section on
#   troubleshooting names each variable that the preflight checks refuse;
# - the differences between the targets list db-superuser, the connection
#   mode of the database and the privileges of its user (ENF-02); the
#   Secrets of the local layer are said to be in clear text; each profile
#   has its memory; nothing is promised on the data after a restart of the
#   node; the teardown of the gcp layer is in two steps, run by a person, and
#   no code block of the README offers an OpenTofu apply or destroy;
# - every public task of the Taskfiles and every workflow has its mention;
# - a line marked "À venir" names the step that delivers it, so that the
#   marks can be found and removed when the step lands.
#
# Usage: s18-readme.sh [root [catalog]]. Without an argument the root is the
# golden repo, the catalog the one of CELIAN when it exists, and the cases of
# tests/static/s18-cases/cases.sh run first. With arguments, only that root
# is checked; the cases use it.
set -euo pipefail

if [ "$#" -gt 2 ]; then
  echo "usage: s18-readme.sh [root [catalog]]" >&2
  exit 2
fi

here="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
catalog=""
if [ "$#" -ge 1 ]; then
  root="$(CDPATH='' cd -- "$1" && pwd)"
  catalog="${2:-}"
else
  root="$(CDPATH='' cd -- "$here/../.." && pwd)"
  catalog="$root/../../catalog/kubernetes-cluster.yaml"
  bash "$here/s18-cases/cases.sh"
fi

readme="$root/README.md"
checks="$root/local/scripts/lib/preflight-checks.sh"
problems=0

report() {
  problems=$((problems + 1))
  printf 'README.md: %s\n' "$1"
}

for file in "$readme" "$checks" "$root/platform.yaml" "$root/Taskfile.yml" \
  "$root/local/tasks/local.yml" "$root/tests/tools/install.sh"; do
  if [ ! -f "$file" ]; then
    printf '%s is missing: the README is checked against it.\n' "$file" >&2
    exit 1
  fi
done

# Removes the white space around $1, and the backticks.
trim() {
  local text="${1//\`/}"
  text="${text#"${text%%[![:space:]]*}"}"
  text="${text%"${text##*[![:space:]]}"}"
  printf '%s' "$text"
}

# The value of NAME in $2, written NAME="value", NAME=value or NAME: "value",
# with or without readonly in front.
value_of() {
  awk -v name="$1" '
    {
      line = $0
      sub(/^readonly[ \t]+/, "", line)
      sub(/^[ \t]+/, "", line)
      if (index(line, name "=") == 1) { line = substr(line, length(name) + 2) }
      else if (index(line, name ": ") == 1) { line = substr(line, length(name) + 3) }
      else { next }
      gsub(/["'"'"']/, "", line)
      print line
      exit
    }' "$2"
}

# The lines of the section whose heading line is $1 (the "#" signs and the
# text), up to the next heading of the same level or above. A "#" line inside
# a code block is not a heading.
section() {
  awk -v head="$1" '
    function level(text,   n) { n = 0; while (substr(text, n + 1, 1) == "#") n++; return n }
    /^```/ { fence = !fence }
    {
      if (!fence && $0 ~ /^#+ /) {
        if (on && level($0) <= want) exit
        if ($0 == head) { on = 1; want = level($0); next }
      }
      if (on) print
    }' "$readme"
}

has_heading() {
  grep -q -x -F -- "$1" "$readme"
}

# The heading line of the README whose text, without backticks, is $1.
heading_line() {
  local line
  while IFS= read -r line; do
    if [ "$(trim "$line")" = "$1" ]; then
      printf '%s' "$line"
      return 0
    fi
  done < <(grep -E '^#{1,6} ' "$readme")
  return 1
}

# ---- the section that the refusals of task up name -----------------------
ref="$(awk -F'section "' '/^readonly README_REF=/ { split($2, part, "\""); print part[1]; exit }' "$checks")"
if [ -z "$ref" ]; then
  report "README_REF is not found in local/scripts/lib/preflight-checks.sh: the refusals of task up name no section."
else
  heading_line "## $ref" >/dev/null ||
    report "no section \"$ref\", which every refusal of task up points to (README_REF)."
fi

# ---- the table of tools --------------------------------------------------
today="$(date -u +%Y-%m-%d)"
kind_version="$(value_of KIND_VERSION "$checks")"
engine_min="$(value_of DOCKER_ENGINE_LINUX_MIN "$checks")"
lite_mib="$(value_of LITE_MIN_MIB "$checks")"
standard_mib="$(value_of STANDARD_MIN_MIB "$checks")"
task_version="$(value_of TASK_VERSION "$root/tests/tools/install.sh")"
cluster_minor="$(value_of kubernetes_minor "$root/platform.yaml")"
http_port="$(value_of GATEWAY_HTTP_PORT "$root/local/tasks/local.yml")"
for pair in "kind_version:KIND_VERSION" "engine_min:DOCKER_ENGINE_LINUX_MIN" \
  "lite_mib:LITE_MIN_MIB" "standard_mib:STANDARD_MIN_MIB" "task_version:TASK_VERSION" \
  "cluster_minor:kubernetes_minor" "http_port:GATEWAY_HTTP_PORT"; do
  variable_name="${pair%%:*}"
  if [ -z "${!variable_name}" ]; then
    report "${pair##*:} is not found in the files that hold it: the README cannot be compared."
  fi
done

# True when text $1 holds the fixed string $2.
has() {
  grep -q -F -- "$2" <<<"$1"
}

tools_table="$(section '### Outils' | grep '^|' | tail -n +3 || true)"
if [ -z "$tools_table" ]; then
  report 'no table of tools under "### Outils": each tool needs a version, a licence, a date and a source.'
else
  IFS='|' read -r _ first_name _ first_licence _ <<<"$(head -n 1 <<<"$tools_table")"
  if [ "$(trim "$first_name")" != "Docker Engine" ]; then
    report "the free container engine comes first in the table of tools (R-26): Docker Engine, not $(trim "$first_name")."
  elif ! has "$first_licence" "Apache-2.0"; then
    report "Docker Engine is listed first as the free engine, with the licence Apache-2.0 (found \"$(trim "$first_licence")\")."
  fi
fi

for tool in "Docker Engine" "kind" "kubectl" "Task" "Git"; do
  found=0
  while IFS='|' read -r _ name version licence read_on origin _; do
    name="$(trim "$name")"
    [ "$name" = "$tool" ] || continue
    found=1
    version="$(trim "$version")"
    licence="$(trim "$licence")"
    read_on="$(trim "$read_on")"
    origin="$(trim "$origin")"
    # An address in a table is written <https://...>, which markdownlint accepts.
    origin="${origin#<}"
    origin="${origin%>}"
    [ -n "$version" ] || report "$tool has no version in the table of tools."
    [ -n "$licence" ] || report "$tool has no licence in the table of tools."
    case "$read_on" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
      *) report "$tool has no date of the form YYYY-MM-DD in the table of tools (found \"$read_on\")." ;;
    esac
    if [[ $read_on > $today ]]; then
      report "$tool is dated $read_on, after today ($today)."
    fi
    case "$origin" in
      https://*) ;;
      *) report "$tool has no https source in the table of tools." ;;
    esac
    case "$tool" in
      "Docker Engine")
        case "$version" in *"$engine_min"*) ;; *) report "Docker Engine: the version column does not say $engine_min, DOCKER_ENGINE_LINUX_MIN of the preflight checks." ;; esac
        ;;
      kind)
        case "$version" in *"$kind_version"*) ;; *) report "kind: the version column does not say $kind_version, KIND_VERSION of the preflight checks." ;; esac
        ;;
      kubectl)
        low="${cluster_minor%%.*}.$((${cluster_minor#*.} - 1))"
        high="${cluster_minor%%.*}.$((${cluster_minor#*.} + 1))"
        case "$version" in *"$low à $high"*) ;; *) report "kubectl: the version column does not say \"$low à $high\", the minors around the $cluster_minor of platform.yaml." ;; esac
        ;;
      Task)
        case "$version" in *"$task_version"*) ;; *) report "Task: the version column does not say $task_version, TASK_VERSION of tests/tools/install.sh." ;; esac
        ;;
    esac
  done <<<"$tools_table"
  [ "$found" -eq 1 ] || report "the table of tools has no row for $tool."
done

# The free engine is also named first in the text.
engine_line="$(grep -n -m 1 -F 'Docker Engine' "$readme" | cut -d: -f1 || true)"
for other in "Docker Desktop" "OrbStack" "Podman"; do
  other_line="$(grep -n -m 1 -F "$other" "$readme" | cut -d: -f1 || true)"
  if [ -n "$other_line" ] && { [ -z "$engine_line" ] || [ "$other_line" -lt "$engine_line" ]; }; then
    report "$other is named at line $other_line, before the free engine, Docker Engine (R-26, ADR-004, condition 8)."
  fi
done

# ---- the install procedure of kind, against the catalog -------------------
kind_section="$(section '### Installer kind')"
kind_rows="$(grep '^|' <<<"$kind_section" | tail -n +3 || true)"
catalog_sums=""
if [ -n "$catalog" ] && [ -f "$catalog" ]; then
  catalog_sums="$(awk '
    /^  local:/ { inlocal = 1; next }
    /^  [a-z]+:/ { inlocal = 0 }
    inlocal && /^    version:/ { value = $2; gsub(/"/, "", value); print "version " value }
    inlocal && /- platform:/ { platform = $3 }
    inlocal && /sha256:/ && platform != "" { value = $2; gsub(/"/, "", value); print platform " " value; platform = "" }
  ' "$catalog")"
  catalog_version="$(printf '%s\n' "$catalog_sums" | awk '$1 == "version" { print $2; exit }')"
  if [ -n "$catalog_version" ] && [ "$catalog_version" != "$kind_version" ]; then
    report "kind $kind_version in the preflight checks, $catalog_version in the catalog: the README follows neither until they agree."
  fi
fi
for platform in darwin-arm64 darwin-amd64 linux-amd64 linux-arm64; do
  sum=""
  while IFS='|' read -r _ name value _; do
    if [ "$(trim "$name")" = "$platform" ]; then
      sum="$(trim "$value")"
    fi
  done <<<"$kind_rows"
  if ! [[ $sum =~ ^[0-9a-f]{64}$ ]]; then
    report "kind: no SHA-256 of 64 hexadecimal digits for $platform under \"### Installer kind\"."
    continue
  fi
  expected="$(printf '%s\n' "$catalog_sums" | awk -v p="$platform" '$1 == p { print $2; exit }')"
  if [ -n "$catalog_sums" ] && [ "$sum" != "$expected" ]; then
    report "kind: the SHA-256 of $platform differs from the catalog (README $sum, catalog ${expected:-absent}): ADR-004, condition 5."
  fi
done
has "$kind_section" "v$kind_version" ||
  report "the install procedure of kind does not name v$kind_version in its download address."

# ---- memory by profile and the address ------------------------------------
lite_lines="$(grep -i -F 'lite' "$readme" || true)"
standard_lines="$(grep -i -F 'standard' "$readme" || true)"
has "$lite_lines" "$lite_mib" ||
  report "no line gives the memory of the lite profile, $lite_mib MiB (LITE_MIN_MIB)."
has "$standard_lines" "$standard_mib" ||
  report "no line gives the memory of the standard profile, $standard_mib MiB (STANDARD_MIN_MIB)."
for address in "http://localhost:$http_port/" "http://localhost:$http_port/api/"; do
  grep -q -F "$address" "$readme" || report "the address $address, printed by task up, is not in the README."
done

# The tools that the preflight checks look for, and the HTTPS listener with
# its self-signed certificate (the second PR of step 7).
# shellcheck disable=SC2016 # backticks of a Markdown heading, not a command
controls="$(section '### Contrôles de `task up`')"
for tool in openssl awk; do
  if grep -q -F "command -v $tool" "$checks"; then
    has "$controls" "\`$tool\`" ||
      report "the preflight checks look for $tool, and the table of the checks does not list it."
  fi
done
https_port="$(value_of GATEWAY_HTTPS_PORT "$root/local/tasks/local.yml")"
if [ -n "$https_port" ]; then
  https_lines="$(grep -F "$https_port" "$readme" || true)"
  has "$https_lines" 'auto-signé' ||
    report "no line gives the HTTPS port $https_port with its self-signed certificate (\"auto-signé\")."
fi

# ---- differences between the targets, secrets, teardown -------------------
for headline in '## Écarts entre les cibles' '## Sécurité' '## Dépannage' '### Démontage en deux temps'; do
  has_heading "$headline" || report "no section \"$headline\"."
done
differences="$(section '## Écarts entre les cibles')"
for word in db-superuser DATABASE_SSL_MODE cloudsqlsuperuser; do
  has "$differences" "$word" ||
    report "the differences between the targets do not mention $word (ENF-02)."
done
clear_lines="$(section '## Sécurité' | grep -i -F 'en clair' || true)"
has "$clear_lines" 'Secret' ||
  report 'the section on security does not say that the Secrets of the local cluster are in clear text ("en clair").'
restart_lines="$(grep -F 'redémarrage du nœud' "$readme" || true)"
has "$restart_lines" 'ne promet' ||
  report 'the README does not say that it promises nothing on the data after a restart of the node.'
teardown="$(section '### Démontage en deux temps')"
for word in deletion_protection 'tofu destroy' facturation personne; do
  has "$teardown" "$word" ||
    report "the teardown in two steps does not mention \"$word\"."
done
offers="$(awk '
  /^```/ { fence = !fence; next }
  fence && $0 ~ /^[ \t]*(tofu|terraform)[ \t]+(apply|destroy|import)/ { print NR }
' "$readme")"
for number in $offers; do
  report "line $number: a code block offers an OpenTofu apply or destroy; the README describes the teardown, a person runs it."
done

# ---- tasks, workflows, variables of the refusals ---------------------------
task_names() {
  awk -v prefix="$2" '
    /^tasks:/ { on = 1; next }
    on && /^[^ #]/ { on = 0 }
    on && /^  [a-z][a-z0-9:_-]*:[ \t]*$/ { name = $1; sub(/:$/, "", name); print prefix name }
  ' "$1"
}
all_tasks="$(task_names "$root/Taskfile.yml" "")"
if [ -f "$root/gcp/tasks/gcp.yml" ]; then
  all_tasks="$all_tasks
$(task_names "$root/gcp/tasks/gcp.yml" "gcp:")"
fi
for name in $all_tasks; do
  grep -q -E -- "task $name([^a-z0-9:_-]|\$)" "$readme" || report "the public task \"task $name\" is not in the README."
done
for workflow in "$root"/.github/workflows/*.yml; do
  [ -f "$workflow" ] || continue
  grep -q -F "$(basename "$workflow")" "$readme" ||
    report "the workflow $(basename "$workflow") is not in the README."
done
refused="$(grep -o -E '(KIND_EXPERIMENTAL_[A-Z_]+|DOCKER_HOST|DOCKER_CONTEXT)' "$checks" | LC_ALL=C sort -u)"
troubleshooting="$(section '## Dépannage')"
for variable in $refused; do
  has "$troubleshooting" "$variable" ||
    report "the troubleshooting does not mention $variable, which the preflight checks refuse."
done

# ---- marks, links, typography ----------------------------------------------
while IFS=: read -r number text; do
  [ -n "$number" ] || continue
  if ! grep -q -E 'étapes? [0-9]' <<<"$text"; then
    report "line $number is marked \"À venir\" without the step that delivers it."
  fi
done < <(grep -n -F 'À venir' "$readme" || true)
while IFS= read -r link; do
  target="${link#](}"
  target="${target%)}"
  target="${target%%#*}"
  case "$target" in
    '' | http://* | https://* | mailto:* | ../*) continue ;;
  esac
  [ -e "$root/$target" ] || report "the link to $target leads to no file of the golden repo."
done < <(grep -o -E '\]\([^)]+\)' "$readme" || true)
if LC_ALL=C grep -q -F "$(printf '\342\200\224')" "$readme"; then
  report 'the README holds an em dash (U+2014).'
fi

if [ "$problems" -gt 0 ]; then
  exit 1
fi
