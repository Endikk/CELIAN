# S20, API part: the API exposes exactly the routes of its contract, no more,
# no less (spec 001, plan matrix; FR-009). The machine description is the
# OpenAPI 3.1 document src/Api/openapi.json, generated from the API and kept
# equal to it by U01 (research RS-03).
#
# Input: the files given to `conftest test --combine`, a list of objects with
# a `path` and the parsed `contents` (research RS-18): the OpenAPI document,
# and tests/static/s20-contract-routes.yaml, whose `routes` list holds one
# "<METHOD> <path>" per route of the contract.
package api_routes

label := "S20 (FR-009)"

# The HTTP methods an OpenAPI 3.1 path item can hold as operations.
methods := {"get", "put", "post", "delete", "options", "head", "patch", "trace"}

route_pattern := `^(GET|PUT|POST|DELETE|OPTIONS|HEAD|PATCH|TRACE) /api(/[^ ?]*)?$`

openapi_files contains file if {
	some file in input
	regex.match(`(^|/)openapi\.json$`, file.path)
}

contract_files contains file if {
	some file in input
	regex.match(`(^|/)s20-contract-routes\.yaml$`, file.path)
}

deny contains msg if {
	count(openapi_files) != 1
	msg := sprintf("%s: expected one OpenAPI document (src/Api/openapi.json) among the checked files, found %v", [label, count(openapi_files)])
}

deny contains msg if {
	count(contract_files) != 1
	msg := sprintf("%s: expected one list of contract routes (tests/static/s20-contract-routes.yaml), found %v", [label, count(contract_files)])
}

deny contains msg if {
	some file in openapi_files
	version := object.get(file.contents, "openapi", "")
	not openapi_31(version)
	msg := sprintf("%s: %s declares OpenAPI '%v'; the API describes its routes in OpenAPI 3.1 (research RS-03)", [label, file.path, version])
}

openapi_31(version) if {
	is_string(version)
	startswith(version, "3.1.")
}

deny contains msg if {
	some file in contract_files
	some route in object.get(file.contents, "routes", [])
	not valid_route(route)
	msg := sprintf("%s: %s holds '%v', which is not '<METHOD> /api...'", [label, file.path, route])
}

deny contains msg if {
	some file in contract_files
	count(object.get(file.contents, "routes", [])) == 0
	msg := sprintf("%s: %s lists no route", [label, file.path])
}

valid_route(route) if {
	is_string(route)
	regex.match(route_pattern, route)
}

# "<METHOD> <path>" of every operation of the OpenAPI document.
described contains route if {
	some file in openapi_files
	some path, item in object.get(file.contents, "paths", {})
	some method, _ in item
	method in methods
	route := sprintf("%s %s", [upper(method), path])
}

contract contains route if {
	some file in contract_files
	some route in object.get(file.contents, "routes", [])
	is_string(route)
}

deny contains msg if {
	count(openapi_files) == 1
	count(contract_files) == 1
	some route in described - contract
	msg := sprintf("%s: the API exposes %s, which the contract does not list", [label, route])
}

deny contains msg if {
	count(openapi_files) == 1
	count(contract_files) == 1
	some route in contract - described
	msg := sprintf("%s: the contract lists %s, which the API does not expose", [label, route])
}
