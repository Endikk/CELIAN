# Tests of S01 (image_digests.rego), run by `conftest verify`.
package image_digests

sdk := "mcr.microsoft.com/dotnet/sdk:10.0.404@sha256:bef136a371963aaa46ec97882845ef6f54dec15728bb4b128b1c2a400ffbc9b4"

runtime := "mcr.microsoft.com/dotnet/aspnet:10.0.15@sha256:12b1135f5f8b3c0a214f2a680ff2033dff4f684f445d6c697d9524ceeb303586"

instruction(cmd, value, stage) := {"Cmd": cmd, "Flags": [], "JSON": false, "Stage": stage, "SubCmd": "", "Value": value}

with_flags(cmd, flags, value, stage) := {"Cmd": cmd, "Flags": flags, "JSON": false, "Stage": stage, "SubCmd": "", "Value": value}

dockerfile(path, commands) := [{"path": path, "contents": commands}]

accepted(files) if {
	msgs := deny with input as files
	count(msgs) == 0
}

denied_with(files, fragment) if {
	msgs := deny with input as files
	some msg in msgs
	contains(msg, fragment)
}

multi_stage := [
	instruction("from", [sdk, "AS", "build"], 0),
	instruction("run", ["dotnet publish"], 0),
	instruction("from", ["build", "AS", "test"], 1),
	instruction("run", ["dotnet run"], 1),
	instruction("from", [runtime], 2),
	with_flags("copy", ["--from=build"], ["/app", "."], 2),
]

test_s01_accepts_images_with_a_digest_and_references_to_earlier_stages if {
	accepted(dockerfile("src/Api/Dockerfile", multi_stage))
}

test_s01_accepts_scratch if {
	accepted(dockerfile("src/Api/Dockerfile", [
		instruction("from", [sdk, "AS", "build"], 0),
		instruction("from", ["scratch"], 1),
		with_flags("copy", ["--from=build"], ["/out/openapi.json", "/"], 1),
	]))
}

test_s01_accepts_an_image_under_saas_b2b_invalid if {
	accepted(dockerfile("Dockerfile", [instruction("from", ["saas-b2b.invalid/api:dev"], 0)]))
}

test_s01_accepts_a_stage_name_in_another_case if {
	accepted(dockerfile("Dockerfile", [
		instruction("from", [sdk, "as", "Build"], 0),
		instruction("from", ["BUILD"], 1),
	]))
}

test_s01_accepts_copy_from_an_earlier_stage_index if {
	accepted(dockerfile("Dockerfile", [
		instruction("from", [sdk], 0),
		instruction("from", [runtime], 1),
		with_flags("copy", ["--from=0"], ["/app", "."], 1),
	]))
}

test_s01_accepts_a_platform_flag if {
	accepted(dockerfile("Dockerfile", [with_flags("from", ["--platform=linux/amd64"], [sdk], 0)]))
}

test_s01_rejects_an_image_by_tag if {
	denied_with(
		dockerfile("src/Api/Dockerfile", [instruction("from", ["mcr.microsoft.com/dotnet/sdk:10.0.404", "AS", "build"], 0)]),
		"src/Api/Dockerfile: FROM mcr.microsoft.com/dotnet/sdk:10.0.404 names no digest",
	)
}

test_s01_rejects_an_image_without_tag_nor_digest if {
	denied_with(dockerfile("Dockerfile", [instruction("from", ["ubuntu"], 0)]), "FROM ubuntu names no digest")
}

test_s01_rejects_a_short_digest if {
	denied_with(dockerfile("Dockerfile", [instruction("from", ["ubuntu@sha256:abc"], 0)]), "FROM ubuntu@sha256:abc names no digest")
}

test_s01_rejects_a_digest_in_upper_case if {
	denied_with(
		dockerfile("Dockerfile", [instruction("from", ["ubuntu@sha256:BEF136A371963AAA46EC97882845EF6F54DEC15728BB4B128B1C2A400FFBC9B4"], 0)]),
		"names no digest",
	)
}

test_s01_rejects_a_build_argument_in_from if {
	denied_with(
		dockerfile("Dockerfile", [instruction("from", ["${BASE_IMAGE}"], 0)]),
		"FROM ${BASE_IMAGE} uses a build argument",
	)
}

test_s01_rejects_a_build_argument_even_with_a_digest if {
	denied_with(
		dockerfile("Dockerfile", [instruction("from", ["mcr.microsoft.com/dotnet/sdk:${TAG}@sha256:bef136a371963aaa46ec97882845ef6f54dec15728bb4b128b1c2a400ffbc9b4"], 0)]),
		"uses a build argument",
	)
}

test_s01_rejects_an_image_named_like_a_later_stage if {
	denied_with(dockerfile("Dockerfile", [
		instruction("from", ["ubuntu", "AS", "ubuntu"], 0),
		instruction("from", [sdk, "AS", "build"], 1),
	]), "FROM ubuntu names no digest")
}

test_s01_rejects_a_reference_to_its_own_stage_name if {
	denied_with(dockerfile("Dockerfile", [instruction("from", ["node", "AS", "node"], 0)]), "FROM node names no digest")
}

test_s01_rejects_copy_from_an_image_by_tag if {
	denied_with(dockerfile("Dockerfile", [
		instruction("from", [runtime], 0),
		with_flags("copy", ["--from=busybox:1.37"], ["/bin/sh", "/sh"], 0),
	]), "COPY --from=busybox:1.37 names no digest")
}

test_s01_rejects_add_from_an_image_by_tag if {
	denied_with(dockerfile("Dockerfile", [
		instruction("from", [runtime], 0),
		with_flags("add", ["--from=busybox"], ["/bin/sh", "/sh"], 0),
	]), "ADD --from=busybox names no digest")
}

test_s01_rejects_copy_from_a_later_stage_index if {
	denied_with(dockerfile("Dockerfile", [
		instruction("from", [sdk], 0),
		with_flags("copy", ["--from=1"], ["/app", "."], 0),
		instruction("from", [runtime], 1),
	]), "COPY --from=1 names no digest")
}

test_s01_rejects_a_mount_from_an_image_by_tag if {
	denied_with(dockerfile("Dockerfile", [
		instruction("from", [sdk], 0),
		with_flags("run", ["--mount=type=bind,from=alpine:3.22,target=/x"], ["ls /x"], 0),
	]), "RUN --mount from=alpine:3.22 names no digest")
}

test_s01_accepts_a_mount_from_an_earlier_stage if {
	accepted(dockerfile("Dockerfile", [
		instruction("from", [sdk, "AS", "build"], 0),
		instruction("from", [runtime], 1),
		with_flags("run", ["--mount=type=bind,from=build,source=/app,target=/app"], ["ls /app"], 1),
	]))
}

test_s01_rejects_an_input_without_a_dockerfile if {
	denied_with([], "no Dockerfile among the checked files")
}

test_s01_checks_each_dockerfile if {
	files := [
		{"path": "src/Api/Dockerfile", "contents": multi_stage},
		{"path": "src/front/Dockerfile", "contents": [instruction("from", ["nginx:1.30.7-alpine"], 0)]},
	]
	denied_with(files, "src/front/Dockerfile: FROM nginx:1.30.7-alpine names no digest")
}

test_s01_names_its_requirements_in_each_message if {
	msgs := deny with input as dockerfile("Dockerfile", [
		instruction("from", ["ubuntu"], 0),
		instruction("from", ["debian"], 1),
	])
	count(msgs) == 2
	every msg in msgs {
		startswith(msg, "S01 (FR-008;")
	}
}
