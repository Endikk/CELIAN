# S27: the exceptions to the image scan (spec 001, FR-022; research RS-23).
# Each entry names the vulnerability and the image, and carries its
# justification, the date it was written and its expiry date. An entry that
# does not hold is refused here, and ignored by the decision of the scan
# (scan_decision.rego, which reads valid_entries and problems).
#
# Input: the files given to `conftest test --combine`, a list of objects with
# a `path` and the parsed `contents` (research RS-23). An exception file is a
# mapping with an `exceptions` list. Data: data.scan_policy, from
# security/scan-policy.yaml (max_exception_days), and data.scan_today, the
# date of the day as YYYY-MM-DD, written by the task in a temporary file.
#
# An entry holds when:
# - vulnerability, image, justification, written and expires are non-empty
#   strings; vulnerability is one word;
# - image is a repository written in full (registry host, then path), in
#   lower case, without tag or digest, so that a new digest from Renovate
#   does not drop it before its expiry;
# - written and expires are dates YYYY-MM-DD, written at the latest today,
#   expires after written and at most max_exception_days later;
# - today is not after expires, its last valid day.
package scan_exceptions

label := "S27 (FR-022; research RS-23)"

fields := ["vulnerability", "image", "justification", "written", "expires"]

date_layout := "2006-01-02"

date_pattern := `^[0-9]{4}-[0-9]{2}-[0-9]{2}$`

repository_pattern := `^[a-z0-9-]+(\.[a-z0-9-]+)+(:[0-9]+)?(/[a-z0-9]+([._-][a-z0-9]+)*)+$`

identifier_pattern := `^[A-Za-z0-9._:-]+$`

# The date of the day, as nanoseconds, when data.scan_today is a valid date.
today := data.scan_today

today_ns := time.parse_ns(date_layout, today) if {
	is_string(today)
	regex.match(date_pattern, today)
}

max_days := data.scan_policy.max_exception_days if {
	is_number(data.scan_policy.max_exception_days)
	data.scan_policy.max_exception_days >= 1
	floor(data.scan_policy.max_exception_days) == data.scan_policy.max_exception_days
}

exception_files contains file if {
	some file in input
	is_object(file.contents)
	"exceptions" in object.keys(file.contents)
}

# Every entry, as [path, index, entry].
entries contains [file.path, index, entry] if {
	some file in exception_files
	is_array(file.contents.exceptions)
	some index, entry in file.contents.exceptions
}

filled(entry, field) if {
	value := object.get(entry, field, null)
	is_string(value)
	trim_space(value) != ""
}

text(entry, field) := entry[field] if filled(entry, field)

text(entry, field) := "?" if not filled(entry, field)

date_ns(entry, field) := time.parse_ns(date_layout, entry[field]) if {
	filled(entry, field)
	regex.match(date_pattern, entry[field])
}

# The reasons why an entry does not hold, as [path, index, reason].
problems contains [path, index, "it is not a mapping"] if {
	some [path, index, entry] in entries
	not is_object(entry)
}

problems contains [path, index, sprintf("no %s", [field])] if {
	some [path, index, entry] in entries
	is_object(entry)
	some field in fields
	not filled(entry, field)
}

problems contains [path, index, "vulnerability is not an identifier"] if {
	some [path, index, entry] in entries
	filled(entry, "vulnerability")
	not regex.match(identifier_pattern, entry.vulnerability)
}

problems contains [path, index, "image is not a repository written in full, without tag or digest (docker.io/library/postgres)"] if {
	some [path, index, entry] in entries
	filled(entry, "image")
	not regex.match(repository_pattern, entry.image)
}

problems contains [path, index, sprintf("%s is not a date YYYY-MM-DD", [field])] if {
	some [path, index, entry] in entries
	some field in ["written", "expires"]
	filled(entry, field)
	not date_ns(entry, field)
}

problems contains [path, index, sprintf("written after today (%s)", [today])] if {
	some [path, index, entry] in entries
	date_ns(entry, "written") > today_ns
}

problems contains [path, index, "expires on or before written"] if {
	some [path, index, entry] in entries
	date_ns(entry, "expires") <= date_ns(entry, "written")
}

problems contains [path, index, sprintf("expires more than %d days after written", [max_days])] if {
	some [path, index, entry] in entries
	date_ns(entry, "expires") > time.add_date(date_ns(entry, "written"), 0, 0, max_days)
}

problems contains [path, index, sprintf("expired on %s", [entry.expires])] if {
	some [path, index, entry] in entries
	today_ns > date_ns(entry, "expires")
}

# Without the date of the day or the maximum, no entry can be judged.
problems contains [path, index, "no date of the day to judge it"] if {
	some [path, index, _] in entries
	not today_ns
}

problems contains [path, index, "no max_exception_days to judge it"] if {
	some [path, index, _] in entries
	not max_days
}

# The entries that hold, as {"vulnerability", "image", "expires", "path"}.
valid_entries contains {"vulnerability": entry.vulnerability, "image": entry.image, "expires": entry.expires, "path": path} if {
	some [path, index, entry] in entries
	is_object(entry)
	not has_problem(path, index)
}

has_problem(path, index) if {
	some problem in problems
	problem[0] == path
	problem[1] == index
}

# How an entry is named in a message.
entry_name(path, index) := sprintf("%s: entry %d (%s on %s)", [path, index + 1, text(entry, "vulnerability"), text(entry, "image")]) if {
	some [entry_path, entry_index, entry] in entries
	entry_path == path
	entry_index == index
	is_object(entry)
}

entry_name(path, index) := sprintf("%s: entry %d", [path, index + 1]) if {
	some [entry_path, entry_index, entry] in entries
	entry_path == path
	entry_index == index
	not is_object(entry)
}

deny contains msg if {
	some [path, index, reason] in problems
	reason != "it is not a mapping"
	msg := sprintf("%s: %s: %s", [label, entry_name(path, index), reason])
}

deny contains msg if {
	some [path, index, "it is not a mapping"] in problems
	msg := sprintf("%s: %s: entry %d is not a mapping", [label, path, index + 1])
}

deny contains msg if {
	some file in exception_files
	not is_array(file.contents.exceptions)
	msg := sprintf("%s: %s: exceptions must be a list", [label, file.path])
}

deny contains msg if {
	some file in input
	not file in exception_files
	msg := sprintf("%s: %s: no exceptions key; an exception file holds an exceptions list", [label, file.path])
}

deny contains msg if {
	count(exception_files) == 0
	count(input) == 0
	msg := sprintf("%s: no exception file among the checked files", [label])
}

deny contains msg if {
	not today_ns
	msg := sprintf("%s: no date of the day (data.scan_today), as YYYY-MM-DD", [label])
}

deny contains msg if {
	not max_days
	msg := sprintf("%s: no max_exception_days, a whole number of days of 1 or more, in data.scan_policy", [label])
}
