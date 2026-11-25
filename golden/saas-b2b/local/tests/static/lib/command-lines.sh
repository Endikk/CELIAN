# shellcheck shell=bash
# Shared helpers of the static controls that read commands in the tasks and
# the scripts of the local layer: S04 (inventory) and S19 (kubeconfig and
# context). Sourced, never run: tests/run-static.sh runs only the *.sh files
# at the top of local/tests/static/.

# The files that hold the commands of task up and of the other tasks: the
# root Taskfile, the Taskfiles of the local layer and its scripts. Paths
# relative to the golden repo, one per line.
command_files() {
  local file
  for file in Taskfile.yml local/tasks/*.yml local/scripts/*.sh local/scripts/lib/*.sh; do
    [ -f "$file" ] && printf '%s\n' "$file"
  done
}

# logical_lines FILE: prints "<line number><TAB><text>" for each command of
# FILE: comments left out (a "#" at the start of a line, or after a blank),
# lines ended by a backslash joined to the next one, blank results skipped.
# A "#" inside a quoted string after a blank is taken for a comment too:
# the messages of the scripts are written without one.
logical_lines() {
  awk '
    {
      line = $0
      sub(/^[[:space:]]*#.*$/, "", line)
      sub(/[[:space:]]#.*$/, "", line)
      if (joining) { text = text " " line } else { text = line; start = NR }
      if (text ~ /\\$/) { sub(/\\$/, "", text); joining = 1; next }
      joining = 0
      gsub(/[[:space:]]+/, " ", text)
      if (text ~ /[^ ]/) printf "%d\t%s\n", start, text
    }
  ' "$1"
}
