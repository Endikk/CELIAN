# S01: every base image of a Dockerfile carries a digest; only images under
# saas-b2b.invalid, built by task up, are exempt (spec 001, plan matrix; FR-008;
# ADR-004, condition 3; ADR-006, condition 7; ADR-011, condition 4). Step 9
# extends the rule to the rendered manifests: every image of a container of a
# render, init containers included (T086).
#
# Input: the Dockerfiles given to `conftest test --combine`, a list of objects
# with a `path` and the parsed `contents`, one entry per instruction with `Cmd`
# (lower case), `Flags`, `Value` and `Stage` (research RS-18). Checked
# references: the image of each FROM, the source of COPY --from and ADD
# --from, and the source of RUN --mount=...,from=. A reference to an earlier
# stage of the same file, or to scratch, names no image.
package image_digests

label := "S01 (FR-008; ADR-004, condition 3; ADR-006, condition 7; ADR-011, condition 4)"

digest_pattern := `@sha256:[0-9a-f]{64}$`

exempt_pattern := `^saas-b2b\.invalid/`

dockerfiles contains file if {
	some file in input
	is_array(file.contents)
}

# Lower-case name of each stage of a file, by stage index: FROM <image> AS <name>.
stage_names(file) := {stage: lower(cmd.Value[2]) |
	some cmd in file.contents
	cmd.Cmd == "from"
	count(cmd.Value) == 3
	lower(cmd.Value[1]) == "as"
	stage := cmd.Stage
}

# A reference names an earlier stage of the file, by name or by index.
earlier_stage(file, ref, stage) if {
	some index, name in stage_names(file)
	index < stage
	lower(ref) == name
}

earlier_stage(_, ref, stage) if {
	regex.match(`^[0-9]+$`, ref)
	to_number(ref) < stage
}

# Problem with an image reference, or nothing when it is acceptable.
problem(_, ref, _) := "uses a build argument, which hides the image it pulls" if {
	contains(ref, "$")
}

problem(file, ref, stage) := "names no digest (@sha256:<64 hex digits>)" if {
	not contains(ref, "$")
	lower(ref) != "scratch"
	not earlier_stage(file, ref, stage)
	not regex.match(exempt_pattern, ref)
	not regex.match(digest_pattern, ref)
}

# Image references of a file, each as [instruction, reference, stage].
from_references(file) := {[sprintf("FROM %s", [cmd.Value[0]]), cmd.Value[0], cmd.Stage] |
	some cmd in file.contents
	cmd.Cmd == "from"
	count(cmd.Value) > 0
}

copy_references(file) := {[sprintf("%s --from=%s", [upper(cmd.Cmd), ref]), ref, cmd.Stage] |
	some cmd in file.contents
	cmd.Cmd in {"copy", "add"}
	some flag in cmd.Flags
	startswith(flag, "--from=")
	ref := substring(flag, count("--from="), -1)
}

mount_references(file) := {[sprintf("RUN --mount from=%s", [ref]), ref, cmd.Stage] |
	some cmd in file.contents
	cmd.Cmd == "run"
	some flag in cmd.Flags
	startswith(flag, "--mount=")
	some option in split(substring(flag, count("--mount="), -1), ",")
	startswith(option, "from=")
	ref := substring(option, count("from="), -1)
}

all_references(file) := (from_references(file) | copy_references(file)) | mount_references(file)

deny contains msg if {
	count(dockerfiles) == 0
	msg := sprintf("%s: no Dockerfile among the checked files", [label])
}

deny contains msg if {
	some file in dockerfiles
	some [instruction, ref, stage] in all_references(file)
	reason := problem(file, ref, stage)
	msg := sprintf("%s: %s: %s %s", [label, file.path, instruction, reason])
}

# --- Rendered manifests (T086) --------------------------------------------------
#
# A render is a manifest read by `conftest test --combine`: one entry per
# document, its parsed `contents` an object. Every image of a container, an
# init container or an ephemeral container of a pod template or of a pod must
# name a digest, except under saas-b2b.invalid, which task up builds. A field
# named image elsewhere (a ConfigMap, say) is no container.

container_lists := {"containers", "initContainers", "ephemeralContainers"}

rendered_images contains [file.path, doc, image] if {
	some file in input
	doc := file.contents
	is_object(doc)
	walk(doc, [path, image])
	is_string(image)
	last := count(path) - 1
	path[last] == "image"
	list_at := count(path) - 3
	path[list_at] in container_lists
}

describe(doc) := sprintf("%v %v", [object.get(doc, "kind", "object"), object.get(object.get(doc, "metadata", {}), "name", "")])

deny contains msg if {
	some [path, doc, image] in rendered_images
	not regex.match(exempt_pattern, image)
	not regex.match(digest_pattern, image)
	msg := sprintf("%s: %s: %s runs %s, which names no digest (@sha256:<64 hex digits>)", [label, path, describe(doc), image])
}
