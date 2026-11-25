# Tests of S20, API part (api_routes.rego), run by `conftest verify`.
package api_routes

contract_routes := [
	"GET /api/healthz",
	"GET /api/readyz",
	"POST /api/notes",
	"GET /api/notes/{id}",
	"GET /api/notes",
]

operation := {"responses": {"200": {"description": "OK"}}}

described_paths := {
	"/api/healthz": {"get": operation},
	"/api/readyz": {"get": operation},
	"/api/notes": {"post": operation, "get": operation},
	"/api/notes/{id}": {"get": operation, "parameters": [{"name": "id", "in": "path"}]},
}

document(paths) := {"openapi": "3.1.1", "info": {"title": "Api | v1", "version": "1.0.0"}, "paths": paths}

files(doc, routes) := [
	{"path": "src/Api/openapi.json", "contents": doc},
	{"path": "tests/static/s20-contract-routes.yaml", "contents": {"routes": routes}},
]

accepted(input_files) if {
	msgs := deny with input as input_files
	count(msgs) == 0
}

denied_with(input_files, fragment) if {
	msgs := deny with input as input_files
	some msg in msgs
	contains(msg, fragment)
}

test_s20_accepts_the_routes_of_the_contract if {
	accepted(files(document(described_paths), contract_routes))
}

test_s20_rejects_a_route_outside_the_contract if {
	paths := object.union(described_paths, {"/openapi/{documentName}.json": {"get": operation}})
	denied_with(files(document(paths), contract_routes), "the API exposes GET /openapi/{documentName}.json, which the contract does not list")
}

test_s20_rejects_a_method_outside_the_contract if {
	paths := object.union(described_paths, {"/api/notes/{id}": {"get": operation, "delete": operation}})
	denied_with(files(document(paths), contract_routes), "the API exposes DELETE /api/notes/{id}")
}

test_s20_rejects_a_missing_route if {
	paths := object.remove(described_paths, ["/api/readyz"])
	denied_with(files(document(paths), contract_routes), "the contract lists GET /api/readyz, which the API does not expose")
}

test_s20_rejects_a_route_under_another_path if {
	paths := object.union(object.remove(described_paths, ["/api/healthz"]), {"/healthz": {"get": operation}})
	denied_with(files(document(paths), contract_routes), "the API exposes GET /healthz")
}

test_s20_ignores_path_item_fields_that_are_not_operations if {
	accepted(files(document(described_paths), contract_routes))
	described_paths["/api/notes/{id}"].parameters
}

test_s20_rejects_an_openapi_version_other_than_3_1 if {
	doc := object.union(document(described_paths), {"openapi": "3.0.4"})
	denied_with(files(doc, contract_routes), "declares OpenAPI '3.0.4'")
}

test_s20_rejects_a_document_without_version if {
	doc := object.remove(document(described_paths), ["openapi"])
	denied_with(files(doc, contract_routes), "declares OpenAPI ''")
}

test_s20_rejects_a_missing_openapi_document if {
	input_files := [{"path": "tests/static/s20-contract-routes.yaml", "contents": {"routes": contract_routes}}]
	denied_with(input_files, "expected one OpenAPI document (src/Api/openapi.json) among the checked files, found 0")
}

test_s20_rejects_a_missing_contract_list if {
	input_files := [{"path": "src/Api/openapi.json", "contents": document(described_paths)}]
	denied_with(input_files, "expected one list of contract routes")
}

test_s20_rejects_an_empty_contract_list if {
	denied_with(files(document({}), []), "lists no route")
}

test_s20_rejects_a_malformed_contract_route if {
	denied_with(files(document(described_paths), array.concat(contract_routes, ["get /api/x"])), "holds 'get /api/x'")
}

test_s20_rejects_a_contract_route_with_a_query_string if {
	denied_with(files(document(described_paths), array.concat(contract_routes, ["GET /api/notes?limit=<n>"])), "holds 'GET /api/notes?limit=<n>'")
}

test_s20_names_its_requirement_in_each_message if {
	paths := object.union(object.remove(described_paths, ["/api/readyz"]), {"/extra": {"get": operation}})
	msgs := deny with input as files(document(paths), contract_routes)
	count(msgs) == 2
	every msg in msgs {
		startswith(msg, "S20 (FR-009)")
	}
}
