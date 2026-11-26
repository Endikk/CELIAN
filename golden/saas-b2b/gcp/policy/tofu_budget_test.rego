# Tests of S15 for the budget root (tofu_budget.rego), run by `conftest verify`.
# Each case changes one thing in a valid pair of roots, written as conftest
# parses HCL: the budget root under gcp/budget/, the main root under gcp/tofu/.
package tofu_budget

encryption := {
	"key_provider": {"gcp_kms": {"state": [{"kms_encryption_key": "${var.state_encryption_key}", "key_length": 32}]}},
	"method": {"aes_gcm": {"state": [{"keys": "${key_provider.gcp_kms.state}"}]}},
	"state": [{"method": "${method.aes_gcm.state}", "enforced": true}],
	"plan": [{"method": "${method.aes_gcm.state}", "enforced": true}],
}

validated := [{"validation": [{"condition": "${can(regex(\"^[0-9]+$\", var.x))}"}]}]

budget := {
	"billing_account": "${var.billing_account_id}",
	"display_name": "${var.name}-budget",
	"budget_filter": [{
		"projects": ["projects/${var.project_number}"],
		"calendar_period": "MONTH",
		"credit_types_treatment": "EXCLUDE_ALL_CREDITS",
	}],
	"amount": [{"specified_amount": [{"currency_code": "${var.budget_currency}", "units": "${tostring(var.budget_amount)}"}]}],
	"threshold_rules": [
		{"threshold_percent": 0.5},
		{"threshold_percent": 0.9},
		{"threshold_percent": 1},
		{"threshold_percent": 1, "spend_basis": "FORECASTED_SPEND"},
	],
}

valid_budget_root := {
	"terraform": [{
		"backend": {"gcs": [{"prefix": "budget"}]},
		"encryption": [encryption],
	}],
	"provider": {"google": [{"project": "${var.project_id}", "billing_project": "${var.project_id}", "user_project_override": true}]},
	"variable": {"project_number": validated, "budget_amount": validated},
	"resource": {"google_billing_budget": {"demo": [budget]}},
}

valid_main_root := {
	"terraform": [{"backend": {"gcs": [{"prefix": "main"}]}}],
	"resource": {
		"google_project_iam_member": {"nodes": [{"role": "roles/container.defaultNodeServiceAccount", "member": "serviceAccount:${google_service_account.nodes.email}"}]},
		"google_secret_manager_secret_iam_member": {"db_auth": [{"role": "roles/secretmanager.secretAccessor", "member": "principal://x"}]},
	},
}

files(budget_root, main_root) := [
	{"path": "gcp/budget/main.tf", "contents": budget_root},
	{"path": "gcp/tofu/main.tf", "contents": main_root},
]

# The valid roots after the JSON patch operations ops, on the budget root or on
# the main root.
in_budget(ops) := files(json.patch(valid_budget_root, ops), valid_main_root)

in_main(ops) := files(valid_budget_root, json.patch(valid_main_root, ops))

set(path, value) := [{"op": "add", "path": path, "value": value}]

drop(path) := [{"op": "remove", "path": path}]

swap(path, value) := [{"op": "replace", "path": path, "value": value}]

accepted(input_files) if {
	msgs := deny with input as input_files
	count(msgs) == 0
}

denied_with(input_files, fragment) if {
	msgs := deny with input as input_files
	some msg in msgs
	contains(msg, fragment)
}

b := "/resource/google_billing_budget/demo/0"

test_s15_budget_accepts_valid_roots if {
	accepted(files(valid_budget_root, valid_main_root))
}

test_s15_budget_ignores_an_input_without_opentofu_file if {
	accepted([{"path": "platform.yaml", "contents": {"kubernetes_minor": "1.36"}}])
}

# Budget present.

test_s15_budget_rejects_a_root_without_budget if {
	denied_with(in_budget(drop("/resource/google_billing_budget")), "no google_billing_budget in the budget root")
}

# Amount from a variable, never written in the code.

test_s15_budget_rejects_a_literal_units_string if {
	denied_with(in_budget(set(concat("", [b, "/amount/0/specified_amount/0/units"]), "100")), "units is a literal")
}

test_s15_budget_rejects_a_literal_units_number if {
	denied_with(in_budget(set(concat("", [b, "/amount/0/specified_amount/0/units"]), 100)), "units is a literal")
}

test_s15_budget_rejects_an_amount_without_units if {
	denied_with(in_budget(drop(concat("", [b, "/amount/0/specified_amount/0/units"]))), "specified_amount.units is not written")
}

test_s15_budget_rejects_a_literal_nanos if {
	denied_with(in_budget(set(concat("", [b, "/amount/0/specified_amount/0/nanos"]), 500000000)), "nanos is a literal")
}

test_s15_budget_accepts_nanos_from_a_variable if {
	accepted(in_budget(set(concat("", [b, "/amount/0/specified_amount/0/nanos"]), "${var.budget_amount}")))
}

test_s15_budget_rejects_a_last_period_amount if {
	denied_with(in_budget(set(concat("", [b, "/amount/0/last_period_amount"]), true)), "last_period_amount")
}

test_s15_budget_rejects_a_budget_without_specified_amount if {
	denied_with(in_budget(swap(concat("", [b, "/amount"]), [{}])), "no amount.specified_amount")
}

test_s15_budget_rejects_a_default_on_the_amount_variable if {
	denied_with(in_budget(set("/variable/budget_amount/0/default", 100)), "variable budget_amount has a default")
}

test_s15_budget_rejects_an_amount_variable_without_validation if {
	denied_with(in_budget(drop("/variable/budget_amount/0/validation")), "variable budget_amount has no validation block")
}

test_s15_budget_rejects_an_undeclared_amount_variable if {
	denied_with(in_budget(drop("/variable/budget_amount")), "variable budget_amount, read by the amount, is not declared")
}

# Filter on the project.

test_s15_budget_rejects_a_budget_without_filter if {
	denied_with(in_budget(drop(concat("", [b, "/budget_filter"]))), "no budget_filter block")
}

test_s15_budget_rejects_a_filter_without_projects if {
	denied_with(in_budget(drop(concat("", [b, "/budget_filter/0/projects"]))), "budget_filter.projects is missing or empty")
}

test_s15_budget_rejects_an_empty_projects_list if {
	denied_with(in_budget(swap(concat("", [b, "/budget_filter/0/projects"]), [])), "budget_filter.projects is missing or empty")
}

test_s15_budget_rejects_a_project_written_in_clear if {
	denied_with(in_budget(swap(concat("", [b, "/budget_filter/0/projects"]), ["projects/123456"])), "is not projects/${var.<name>}")
}

test_s15_budget_rejects_a_project_number_without_validation if {
	denied_with(in_budget(drop("/variable/project_number/0/validation")), "variable project_number has no validation block")
}

# Period and credits.

test_s15_budget_rejects_a_filter_without_calendar_period if {
	denied_with(in_budget(drop(concat("", [b, "/budget_filter/0/calendar_period"]))), "calendar_period must be MONTH")
}

test_s15_budget_rejects_a_custom_period if {
	custom := [{"start_date": [{"year": 2026, "month": 12, "day": 1}]}]
	denied_with(in_budget(set(concat("", [b, "/budget_filter/0/custom_period"]), custom)), "custom_period is set")
}

test_s15_budget_rejects_credits_left_to_the_default if {
	denied_with(in_budget(drop(concat("", [b, "/budget_filter/0/credit_types_treatment"]))), "credit_types_treatment is not written")
}

# Thresholds: 50, 90 and 100 % of the actual spend, 100 % of the forecast.

test_s15_budget_rejects_a_missing_50_percent_threshold if {
	denied_with(in_budget(drop(concat("", [b, "/threshold_rules/0"]))), "no threshold_rules at 50 % of CURRENT_SPEND")
}

test_s15_budget_rejects_a_missing_90_percent_threshold if {
	denied_with(in_budget(drop(concat("", [b, "/threshold_rules/1"]))), "no threshold_rules at 90 % of CURRENT_SPEND")
}

test_s15_budget_rejects_a_missing_100_percent_threshold if {
	denied_with(in_budget(drop(concat("", [b, "/threshold_rules/2"]))), "no threshold_rules at 100 % of CURRENT_SPEND")
}

test_s15_budget_rejects_a_missing_forecast_threshold if {
	denied_with(in_budget(drop(concat("", [b, "/threshold_rules/3"]))), "no threshold_rules at 100 % of FORECASTED_SPEND")
}

test_s15_budget_does_not_take_a_forecast_for_the_actual_spend if {
	forecast_only := [
		{"threshold_percent": 0.5},
		{"threshold_percent": 0.9},
		{"threshold_percent": 1, "spend_basis": "FORECASTED_SPEND"},
	]
	denied_with(in_budget(swap(concat("", [b, "/threshold_rules"]), forecast_only)), "no threshold_rules at 100 % of CURRENT_SPEND")
}

test_s15_budget_takes_an_explicit_current_spend if {
	explicit := [
		{"threshold_percent": 0.5, "spend_basis": "CURRENT_SPEND"},
		{"threshold_percent": 0.9},
		{"threshold_percent": 1},
		{"threshold_percent": 1, "spend_basis": "FORECASTED_SPEND"},
	]
	accepted(in_budget(swap(concat("", [b, "/threshold_rules"]), explicit)))
}

# Default recipients kept.

test_s15_budget_rejects_default_recipients_turned_off if {
	rule := {"disable_default_iam_recipients": true, "monitoring_notification_channels": ["projects/p/notificationChannels/1"]}
	denied_with(in_budget(set(concat("", [b, "/all_updates_rule"]), [rule])), "disable_default_iam_recipients is true")
}

test_s15_budget_accepts_an_extra_channel_with_default_recipients if {
	rule := {"monitoring_notification_channels": ["projects/p/notificationChannels/1"]}
	accepted(in_budget(set(concat("", [b, "/all_updates_rule"]), [rule])))
}

# Provider: the quota project of the user's credentials.

test_s15_budget_rejects_a_provider_without_billing_project if {
	denied_with(in_budget(drop("/provider/google/0/billing_project")), "provider google has no billing_project")
}

test_s15_budget_rejects_a_provider_without_user_project_override if {
	denied_with(in_budget(drop("/provider/google/0/user_project_override")), "user_project_override = true")
}

test_s15_budget_rejects_a_user_project_override_turned_off if {
	denied_with(in_budget(swap("/provider/google/0/user_project_override", false)), "user_project_override = true")
}

test_s15_budget_rejects_a_root_without_provider if {
	denied_with(in_budget(drop("/provider")), "no provider google block")
}

# State and plans encrypted, enforced.

test_s15_budget_rejects_a_root_without_encryption if {
	denied_with(in_budget(swap("/terraform/0/encryption", [])), "no terraform.encryption block in the budget root")
}

test_s15_budget_rejects_an_encryption_without_gcp_kms if {
	denied_with(in_budget(set("/terraform/0/encryption/0/key_provider", {"pbkdf2": {"state": [{"passphrase": "${var.p}"}]}})), "has no gcp_kms key provider")
}

test_s15_budget_rejects_a_state_not_enforced if {
	denied_with(in_budget(swap("/terraform/0/encryption/0/state/0/enforced", false)), "no state section with a method and enforced = true")
}

test_s15_budget_rejects_plans_not_enforced if {
	denied_with(in_budget(drop("/terraform/0/encryption/0/plan/0/enforced")), "no plan section with a method and enforced = true")
}

test_s15_budget_rejects_the_unencrypted_method if {
	denied_with(in_budget(set("/terraform/0/encryption/0/method/unencrypted", {"migrate": [{}]})), "unencrypted method")
}

# Own state prefix, distinct from the main root.

test_s15_budget_rejects_a_root_without_gcs_backend if {
	denied_with(in_budget(drop("/terraform/0/backend")), "no gcs backend in the budget root")
}

test_s15_budget_rejects_a_backend_without_prefix if {
	denied_with(in_budget(swap("/terraform/0/backend/gcs/0", {})), "writes no literal prefix")
}

test_s15_budget_rejects_an_empty_prefix if {
	denied_with(in_budget(swap("/terraform/0/backend/gcs/0/prefix", "")), "writes no literal prefix")
}

test_s15_budget_rejects_a_prefix_read_from_a_variable if {
	denied_with(in_budget(swap("/terraform/0/backend/gcs/0/prefix", "${var.prefix}")), "writes no literal prefix")
}

test_s15_budget_rejects_the_prefix_of_the_main_root if {
	denied_with(in_budget(swap("/terraform/0/backend/gcs/0/prefix", "main")), "collides with")
}

test_s15_budget_rejects_a_prefix_inside_the_one_of_the_main_root if {
	denied_with(in_budget(swap("/terraform/0/backend/gcs/0/prefix", "main/budget")), "collides with")
}

test_s15_budget_rejects_a_prefix_that_holds_the_one_of_the_main_root if {
	denied_with(in_main(swap("/terraform/0/backend/gcs/0/prefix", "budget/main")), "collides with")
}

test_s15_budget_accepts_prefixes_that_only_share_letters if {
	accepted(in_main(swap("/terraform/0/backend/gcs/0/prefix", "budgets")))
}

test_s15_budget_rejects_a_main_root_without_prefix if {
	denied_with(in_main(swap("/terraform/0/backend/gcs/0", {})), "gcp/tofu/ writes no literal state prefix")
}

# The identity of the main root holds no base role and no budget role.

test_s15_budget_rejects_owner_in_the_main_root if {
	grant := {"role": "roles/owner", "member": "serviceAccount:x"}
	denied_with(in_main(set("/resource/google_project_iam_member/ci", [grant])), "grants roles/owner")
}

test_s15_budget_rejects_editor_in_the_main_root if {
	grant := {"role": "roles/editor", "member": "serviceAccount:x"}
	denied_with(in_main(set("/resource/google_project_iam_member/ci", [grant])), "grants roles/editor")
}

test_s15_budget_rejects_the_legacy_writer_and_admin_roles if {
	denied_with(in_main(set("/resource/google_project_iam_binding", {"w": [{"role": "roles/writer", "members": ["serviceAccount:x"]}]})), "grants roles/writer")
	denied_with(in_main(set("/resource/google_project_iam_binding", {"a": [{"role": "roles/admin", "members": ["serviceAccount:x"]}]})), "grants roles/admin")
}

test_s15_budget_rejects_the_billing_roles_that_write_budgets if {
	denied_with(in_main(set("/resource/google_billing_account_iam_member", {"c": [{"role": "roles/billing.costsManager", "member": "serviceAccount:x"}]})), "grants roles/billing.costsManager")
	denied_with(in_main(set("/resource/google_billing_account_iam_member", {"a": [{"role": "roles/billing.admin", "member": "serviceAccount:x"}]})), "grants roles/billing.admin")
}

test_s15_budget_rejects_a_base_role_in_a_policy_binding if {
	policy := {"google_iam_policy": {"p": [{"binding": [{"role": "roles/editor", "members": ["serviceAccount:x"]}]}]}}
	denied_with(in_main(set("/data", policy)), "grants roles/editor")
}

test_s15_budget_rejects_a_role_that_is_not_a_literal if {
	denied_with(in_main(set("/resource/google_project_iam_member/v", [{"role": "${var.ci_role}", "member": "serviceAccount:x"}])), "role is not a literal")
}

test_s15_budget_rejects_a_base_role_in_the_budget_root_too if {
	grant := {"role": "roles/owner", "member": "serviceAccount:x"}
	denied_with(in_budget(set("/resource/google_project_iam_member", {"x": [grant]})), "grants roles/owner")
}
