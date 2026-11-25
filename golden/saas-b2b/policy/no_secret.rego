# S03: no Secret is versioned (spec 001, plan, matrix S03; FR-004; ADR-006,
# condition 1; ADR-007, condition 1; principle IX): no object of kind Secret
# in a YAML or JSON file of the repository, at the top of a document or in
# the items of a List, and no secretGenerator in a Kustomization, which
# would build one from a versioned value. On the local target, task up
# creates the Secrets through a pipe (local/scripts/secrets.sh); on GCP,
# Secret Manager feeds them (ADR-007).
#
# Input: the YAML and JSON files of the golden repo given to `conftest test
# --combine`, one entry per document with its `path` and parsed `contents`
# (research RS-18), written by tests/static/s03-no-secret.sh.
package no_secret

label := "S03 (FR-004; ADR-006, condition 1; ADR-007, condition 1)"

# The objects of a document: the document, and the items of a List.
objects(doc) := [doc] if {
	object.get(doc, "kind", null) != "List"
} else := object.get(doc, "items", [])

deny contains msg if {
	some file in input
	is_object(file.contents)
	some obj in objects(file.contents)
	is_object(obj)
	obj.kind == "Secret"
	msg := sprintf("%s: %s holds a Secret, %v; a Secret is created on the machine by task up, or synchronized from Secret Manager on GCP, and never versioned", [label, file.path, object.get(object.get(obj, "metadata", {}), "name", null)])
}

deny contains msg if {
	some file in input
	is_object(file.contents)
	object.get(file.contents, "secretGenerator", null) != null
	msg := sprintf("%s: %s declares a secretGenerator, which builds a Secret from versioned values", [label, file.path])
}
