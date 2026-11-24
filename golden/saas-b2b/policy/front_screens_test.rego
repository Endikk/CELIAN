# Tests of S20, front part (front_screens.rego), run by `conftest verify`.
package front_screens

contract_file := {
	"path": "tests/static/s20-contract-routes.yaml",
	"contents": {"routes": [
		"GET /api/healthz",
		"GET /api/readyz",
		"POST /api/notes",
		"GET /api/notes/{id}",
		"GET /api/notes",
	]},
}

package_file(dependencies) := {
	"path": "src/front/package.json",
	"contents": {"name": "saas-b2b-front", "dependencies": dependencies, "devDependencies": {"vite": "8.3.8"}},
}

good_facts := {
	"screens": ["NotesScreen.tsx"],
	"html_entries": ["index.html"],
	"calls": ["GET /api/notes", "GET /api/notes/{id}", "POST /api/notes"],
	"stray_api": [],
	"forbidden": [],
}

facts_file(facts) := {"path": "/tmp/s20.abc/s20-front-facts.yaml", "contents": facts}

react := {"react": "19.3.1", "react-dom": "19.3.1"}

files(facts, dependencies) := [contract_file, package_file(dependencies), facts_file(facts)]

accepted(input_files) if {
	msgs := deny with input as input_files
	count(msgs) == 0
}

denied_with(input_files, fragment) if {
	msgs := deny with input as input_files
	some msg in msgs
	contains(msg, fragment)
}

test_s20_accepts_the_notes_screen_calling_contract_routes if {
	accepted(files(good_facts, react))
}

test_s20_rejects_a_second_screen if {
	facts := object.union(good_facts, {"screens": ["NotesScreen.tsx", "SettingsScreen.tsx"]})
	denied_with(files(facts, react), "the front has one screen")
}

test_s20_rejects_another_screen_than_the_notes_one if {
	facts := object.union(good_facts, {"screens": ["HomeScreen.tsx"]})
	denied_with(files(facts, react), "src/front/src/screens/ holds [\"HomeScreen.tsx\"]")
}

test_s20_rejects_no_screen if {
	facts := object.union(good_facts, {"screens": []})
	denied_with(files(facts, react), "the front has one screen")
}

test_s20_rejects_a_second_html_page if {
	facts := object.union(good_facts, {"html_entries": ["admin.html", "index.html"]})
	denied_with(files(facts, react), "the front has one page")
}

test_s20_rejects_a_call_outside_the_contract if {
	facts := object.union(good_facts, {"calls": array.concat(good_facts.calls, ["DELETE /api/notes/{id}"])})
	denied_with(files(facts, react), "the front calls DELETE /api/notes/{id}, which the contract does not list")
}

test_s20_rejects_a_front_that_never_reads_a_note if {
	facts := object.union(good_facts, {"calls": ["GET /api/notes", "POST /api/notes"]})
	denied_with(files(facts, react), "the front never calls GET /api/notes/{id}")
}

test_s20_accepts_a_call_to_a_health_route_of_the_contract if {
	facts := object.union(good_facts, {"calls": array.concat(good_facts.calls, ["GET /api/healthz"])})
	accepted(files(facts, react))
}

test_s20_rejects_a_path_under_api_outside_a_route_literal if {
	facts := object.union(good_facts, {"stray_api": ["src/screens/NotesScreen.tsx:12"]})
	denied_with(files(facts, react), "src/screens/NotesScreen.tsx:12 holds a string that starts with /api")
}

test_s20_reports_each_forbidden_line if {
	facts := object.union(good_facts, {"forbidden": ["src/main.tsx:3: uses import.meta.env, a configured value"]})
	denied_with(files(facts, react), "src/main.tsx:3: uses import.meta.env")
}

test_s20_rejects_a_router_dependency if {
	dependencies := object.union(react, {"react-router": "7.0.0"})
	denied_with(files(good_facts, dependencies), "depends at run time on [\"react\", \"react-dom\", \"react-router\"]")
}

test_s20_rejects_a_front_without_react_dom if {
	denied_with(files(good_facts, {"react": "19.3.1"}), "the front needs [\"react\", \"react-dom\"] only")
}

test_s20_rejects_missing_inputs if {
	denied_with([contract_file], "expected one src/front/package.json among the checked files, found 0")
	denied_with([contract_file], "expected one s20-front-facts.yaml among the checked files, found 0")
}

test_s20_names_its_requirement_in_each_message if {
	facts := object.union(good_facts, {"screens": [], "stray_api": ["src/api.ts:4"]})
	msgs := deny with input as files(facts, {})
	count(msgs) == 3
	every msg in msgs {
		startswith(msg, "S20 (FR-009): ")
	}
}
