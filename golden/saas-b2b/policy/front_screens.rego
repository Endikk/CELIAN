# S20, front part: the front has one screen, the notes screen, and calls
# only the routes of the API contract, by relative paths, with no other
# network channel (spec 001, plan matrix; FR-009).
#
# Input: the files given to `conftest test --combine`, a list of objects with
# a `path` and the parsed `contents` (research RS-18):
# - src/front/package.json, whose runtime dependencies must be React alone:
#   no router, no HTTP client, no measurement library;
# - tests/static/s20-contract-routes.yaml, the routes of the contract;
# - s20-front-facts.yaml, written by tests/static/s20-front-screens.sh from
#   the sources of src/front/src/: `screens` (files of src/screens/),
#   `html_entries` (HTML files of src/front/), `calls` (every literal
#   "<METHOD> /api..." of the sources), `stray_api` (lines with a string that
#   starts with /api outside such a literal) and `forbidden` (lines that use
#   a channel or a setting the front must not have).
package front_screens

label := "S20 (FR-009)"

expected_screens := {"NotesScreen.tsx"}

expected_html_entries := {"index.html"}

expected_dependencies := {"react", "react-dom"}

# What the front needs from the contract: the list on load, the add form,
# and the read that tells where a note came from (contracts/http-api.md).
required_calls := {"GET /api/notes", "POST /api/notes", "GET /api/notes/{id}"}

files_named(pattern) := {file |
	some file in input
	regex.match(pattern, file.path)
}

package_files := files_named(`(^|/)src/front/package\.json$`)

contract_files := files_named(`(^|/)s20-contract-routes\.yaml$`)

facts_files := files_named(`(^|/)s20-front-facts\.yaml$`)

deny contains msg if {
	some [name, found] in [
		["src/front/package.json", count(package_files)],
		["tests/static/s20-contract-routes.yaml", count(contract_files)],
		["s20-front-facts.yaml", count(facts_files)],
	]
	found != 1
	msg := sprintf("%s: expected one %s among the checked files, found %v", [label, name, found])
}

fact(name) := {value |
	some file in facts_files
	some value in object.get(file.contents, name, [])
}

contract := {route |
	some file in contract_files
	some route in object.get(file.contents, "routes", [])
}

dependencies := {name |
	some file in package_files
	some name, _ in object.get(file.contents, "dependencies", {})
}

deny contains msg if {
	count(facts_files) == 1
	fact("screens") != expected_screens
	msg := sprintf("%s: src/front/src/screens/ holds %v; the front has one screen, %v", [label, sort_set(fact("screens")), sort_set(expected_screens)])
}

deny contains msg if {
	count(facts_files) == 1
	fact("html_entries") != expected_html_entries
	msg := sprintf("%s: src/front/ holds the HTML files %v; the front has one page, %v", [label, sort_set(fact("html_entries")), sort_set(expected_html_entries)])
}

deny contains msg if {
	count(contract_files) == 1
	some call in fact("calls")
	not call in contract
	msg := sprintf("%s: the front calls %s, which the contract does not list", [label, call])
}

deny contains msg if {
	count(facts_files) == 1
	some call in required_calls - fact("calls")
	msg := sprintf("%s: the front never calls %s, which the notes screen needs", [label, call])
}

deny contains msg if {
	some line in fact("stray_api")
	msg := sprintf("%s: %s holds a string that starts with /api outside a route literal \"<METHOD> /api...\"", [label, line])
}

deny contains msg if {
	some line in fact("forbidden")
	msg := sprintf("%s: %s", [label, line])
}

deny contains msg if {
	count(package_files) == 1
	dependencies != expected_dependencies
	msg := sprintf("%s: src/front/package.json depends at run time on %v; the front needs %v only", [label, sort_set(dependencies), sort_set(expected_dependencies)])
}

sort_set(values) := sort([value | some value in values])
