# S15: the budget root of the gcp layer, gcp/budget/ (T110; ADR-008, question
# 1; constitution, principle X). Three things:
# - the alert: one google_billing_budget on the project, its amount from a
#   variable with no default (R-05: no amount is chosen before [FINOPS]
#   validates one), thresholds at 50, 90 and 100 % of the actual spend and 100
#   % of the forecast, the default recipients kept;
# - the root itself: state and plans encrypted and enforced, a literal state
#   prefix of its own that differs from the one of gcp/tofu/, and the quota
#   project that the credentials of a user need;
# - the identity of the main root: no base role (Owner, Editor, Admin, Writer)
#   and no billing role that writes budgets, in any IAM resource of either
#   root (conditions of [SECU]).
#
# Input: the files given to `conftest test --combine`, a list of objects with
# a `path` and the parsed `contents` (research RS-18): the .tf files of both
# roots. What sits under gcp/tofu/ is the main root; every other .tf file is
# read as the budget root, which is how a case of testdata/ stands for it.
# Sources of the facts: research RS-26.
package tofu_budget

label(topic) := sprintf("S15 (T110; ADR-008, question 1; %s)", [topic])

tf_files contains file if {
	some file in input
	endswith(file.path, ".tf")
}

main_file(file) if contains(file.path, "gcp/tofu/")

main_files contains file if {
	some file in tf_files
	main_file(file)
}

budget_files contains file if {
	some file in tf_files
	not main_file(file)
}

budget_resources contains {"path": file.path, "type": type, "name": name, "body": body} if {
	some file in budget_files
	some type, named in object.get(file.contents, "resource", {})
	some name, bodies in named
	some body in bodies
}

budgets := {block | some block in budget_resources; block.type == "google_billing_budget"}

where(block) := sprintf("%s: %s.%s", [block.path, block.type, block.name])

# First body of nested block `key` of `body`, or an empty object.
first(body, key) := object.get(body, key, [{}])[0]

# The names N of the var.N that a value reads.
var_refs(value) := {name |
	some match in regex.find_all_string_submatch_n(`var\.([A-Za-z0-9_]+)`, sprintf("%v", [value]), -1)
	name := match[1]
}

variable_named(name) := {{"path": file.path, "body": body} |
	some file in budget_files
	some body in object.get(file.contents, ["variable", name], [])
}

# Budget present.

deny contains msg if {
	count(tf_files) > 0
	count(budgets) == 0
	msg := sprintf("%s: no google_billing_budget in the budget root; ENF-05 wants the alert declared in the code", [label("budget")])
}

# Amount: from a variable with no default and a validation block, never
# written in the code. last_period_amount takes the spend of the last period,
# so a month that runs away raises its own ceiling.

amount_of(budget) := first(budget.body, "amount")

specified_of(budget) := first(amount_of(budget), "specified_amount")

amount_keys := ["units", "nanos"]

deny contains msg if {
	some budget in budgets
	object.get(amount_of(budget), "last_period_amount", false) != false
	msg := sprintf("%s: %s: amount.last_period_amount follows the spend of the last period; write amount.specified_amount from a variable", [label("amount"), where(budget)])
}

deny contains msg if {
	some budget in budgets
	count(object.get(amount_of(budget), "specified_amount", [])) == 0
	msg := sprintf("%s: %s: no amount.specified_amount; the amount comes from a variable (R-05)", [label("amount"), where(budget)])
}

deny contains msg if {
	some budget in budgets
	count(object.get(amount_of(budget), "specified_amount", [])) > 0
	object.get(specified_of(budget), "units", null) == null
	msg := sprintf("%s: %s: specified_amount.units is not written; the amount would be 0", [label("amount"), where(budget)])
}

deny contains msg if {
	some budget in budgets
	some key in amount_keys
	value := object.get(specified_of(budget), key, null)
	value != null
	count(var_refs(value)) == 0
	msg := sprintf("%s: %s: specified_amount.%s is a literal; the amount comes from a variable with no default (R-05)", [label("amount"), where(budget), key])
}

amount_vars contains name if {
	some budget in budgets
	some key in amount_keys
	value := object.get(specified_of(budget), key, null)
	value != null
	some name in var_refs(value)
}

# Filter: the project, by "projects/${var.<name>}", on a calendar month, with
# the credits written out. A budget without projects counts the whole billing
# account. FORECASTED_SPEND exists for a calendar period only.

filter_of(budget) := first(budget.body, "budget_filter")

projects_of(budget) := projects if {
	projects := object.get(filter_of(budget), "projects", [])
	is_array(projects)
} else := []

project_entry := `^projects/\$\{var\.[A-Za-z0-9_]+\}$`

deny contains msg if {
	some budget in budgets
	count(object.get(budget.body, "budget_filter", [])) == 0
	msg := sprintf("%s: %s: no budget_filter block; the budget would count the whole billing account", [label("filter"), where(budget)])
}

deny contains msg if {
	some budget in budgets
	count(projects_of(budget)) == 0
	msg := sprintf("%s: %s: budget_filter.projects is missing or empty; the budget would count the whole billing account", [label("filter"), where(budget)])
}

deny contains msg if {
	some budget in budgets
	some entry in projects_of(budget)
	not regex.match(project_entry, sprintf("%v", [entry]))
	msg := sprintf("%s: %s: budget_filter.projects entry '%v' is not projects/${var.<name>}; the project number comes from a variable", [label("filter"), where(budget), entry])
}

project_vars contains name if {
	some budget in budgets
	some entry in projects_of(budget)
	some name in var_refs(entry)
}

deny contains msg if {
	some budget in budgets
	object.get(filter_of(budget), "calendar_period", "") != "MONTH"
	msg := sprintf("%s: %s: budget_filter.calendar_period must be MONTH; the forecast threshold needs a calendar period", [label("filter"), where(budget)])
}

deny contains msg if {
	some budget in budgets
	count(object.get(filter_of(budget), "custom_period", [])) > 0
	msg := sprintf("%s: %s: budget_filter.custom_period is set; a custom period does not recur and gets no forecast alert", [label("filter"), where(budget)])
}

deny contains msg if {
	some budget in budgets
	object.get(filter_of(budget), "credit_types_treatment", "") == ""
	msg := sprintf("%s: %s: budget_filter.credit_types_treatment is not written; the default hides a free trial or a promotion from the spend", [label("filter"), where(budget)])
}

# The variables behind the amount and the project: declared, no default, a
# validation block.

checked_variables contains {"name": name, "topic": "amount"} if {
	some name in amount_vars
}

checked_variables contains {"name": name, "topic": "budget filter"} if {
	some name in project_vars
}

deny contains msg if {
	some checked in checked_variables
	count(variable_named(checked.name)) == 0
	msg := sprintf("%s: variable %s, read by the %s, is not declared", [label("variables"), checked.name, checked.topic])
}

deny contains msg if {
	some checked in checked_variables
	some variable in variable_named(checked.name)
	"default" in object.keys(variable.body)
	msg := sprintf("%s: %s: variable %s has a default; no value is chosen here before [FINOPS] validates one (R-05)", [label("variables"), variable.path, checked.name])
}

deny contains msg if {
	some checked in checked_variables
	some variable in variable_named(checked.name)
	count(object.get(variable.body, "validation", [])) == 0
	msg := sprintf("%s: %s: variable %s has no validation block", [label("variables"), variable.path, checked.name])
}

# Thresholds: 50, 90 and 100 % of the actual spend, which are the defaults of
# the console, and 100 % of the forecast. spend_basis defaults to
# CURRENT_SPEND.

required_thresholds := [
	{"percent": 0.5, "basis": "CURRENT_SPEND", "label": "50 %"},
	{"percent": 0.9, "basis": "CURRENT_SPEND", "label": "90 %"},
	{"percent": 1, "basis": "CURRENT_SPEND", "label": "100 %"},
	{"percent": 1, "basis": "FORECASTED_SPEND", "label": "100 %"},
]

threshold_set(budget) := {{"percent": rule.threshold_percent, "basis": object.get(rule, "spend_basis", "CURRENT_SPEND")} |
	some rule in object.get(budget.body, "threshold_rules", [])
	is_number(object.get(rule, "threshold_percent", null))
}

deny contains msg if {
	some budget in budgets
	some threshold in required_thresholds
	not {"percent": threshold.percent, "basis": threshold.basis} in threshold_set(budget)
	msg := sprintf("%s: %s: no threshold_rules at %s of %s", [label("thresholds"), where(budget), threshold.label, threshold.basis])
}

# Recipients: the default ones, the Billing Account Administrators and Users,
# stay on.

deny contains msg if {
	some budget in budgets
	some rule in object.get(budget.body, "all_updates_rule", [])
	object.get(rule, "disable_default_iam_recipients", false) == true
	msg := sprintf("%s: %s: all_updates_rule.disable_default_iam_recipients is true; the default recipients stay on", [label("recipients"), where(budget)])
}

# Provider: with the credentials of a user, the Billing Budgets API answers
# 403 unless a quota project is named and user_project_override is true.

google_providers contains provider if {
	some file in budget_files
	some provider in object.get(file.contents, ["provider", "google"], [])
}

deny contains msg if {
	count(budget_files) > 0
	count(google_providers) == 0
	msg := sprintf("%s: no provider google block in the budget root; it names the quota project (billing_project, user_project_override)", [label("provider")])
}

deny contains msg if {
	some provider in google_providers
	object.get(provider, "billing_project", "") == ""
	msg := sprintf("%s: provider google has no billing_project; the Billing Budgets API answers 403 to the credentials of a user", [label("provider")])
}

deny contains msg if {
	some provider in google_providers
	object.get(provider, "user_project_override", false) != true
	msg := sprintf("%s: provider google has no user_project_override = true; billing_project is ignored without it", [label("provider")])
}

# State and plans encrypted by OpenTofu with a Cloud KMS key, and refused
# unencrypted: the same as the main root (ADR-008, condition 2).

encryptions contains encryption if {
	some file in budget_files
	some settings in object.get(file.contents, "terraform", [])
	some encryption in object.get(settings, "encryption", [])
}

deny contains msg if {
	count(budget_files) > 0
	count(encryptions) == 0
	msg := sprintf("%s: no terraform.encryption block in the budget root; the state and the plans must be encrypted", [label("encryption")])
}

deny contains msg if {
	count(encryptions) > 0
	not some_gcp_kms
	msg := sprintf("%s: the encryption has no gcp_kms key provider", [label("encryption")])
}

some_gcp_kms if {
	some encryption in encryptions
	count(object.get(encryption, ["key_provider", "gcp_kms"], {})) > 0
}

enforced(target) if {
	some encryption in encryptions
	some section in object.get(encryption, target, [])
	section.enforced == true
	startswith(object.get(section, "method", ""), "${method.")
}

deny contains msg if {
	count(encryptions) > 0
	some target in ["state", "plan"]
	not enforced(target)
	msg := sprintf("%s: the encryption block has no %s section with a method and enforced = true", [label("encryption"), target])
}

deny contains msg if {
	some encryption in encryptions
	count(object.get(encryption, ["method", "unencrypted"], {})) > 0
	msg := sprintf("%s: the unencrypted method is declared; it only serves a migration, never the code of the root", [label("encryption")])
}

# State prefix: written as a literal, and neither equal to the one of gcp/tofu/
# nor nested with it. A -backend-config at init overrides the written prefix
# and no file shows it: the README of the budget root forbids it.

backends_of(files) := {backend |
	some file in files
	some settings in object.get(file.contents, "terraform", [])
	some backend in object.get(settings, ["backend", "gcs"], [])
}

literal_prefix(backend) := prefix if {
	prefix := object.get(backend, "prefix", "")
	is_string(prefix)
	prefix != ""
	not contains(prefix, "${")
}

deny contains msg if {
	count(budget_files) > 0
	count(backends_of(budget_files)) == 0
	msg := sprintf("%s: no gcs backend in the budget root; its state has a prefix of its own", [label("state prefix")])
}

deny contains msg if {
	some backend in backends_of(budget_files)
	not literal_prefix(backend)
	msg := sprintf("%s: the gcs backend of the budget root writes no literal prefix; its state would take the one given at init", [label("state prefix")])
}

budget_prefixes contains prefix if {
	some backend in backends_of(budget_files)
	prefix := literal_prefix(backend)
}

main_prefixes contains prefix if {
	some backend in backends_of(main_files)
	prefix := literal_prefix(backend)
}

deny contains msg if {
	count(main_files) > 0
	count(main_prefixes) == 0
	msg := sprintf("%s: gcp/tofu/ writes no literal state prefix; it cannot be shown to differ from the one of the budget root", [label("state prefix")])
}

collides(a, b) if a == b

collides(a, b) if startswith(a, concat("", [b, "/"]))

collides(a, b) if startswith(b, concat("", [a, "/"]))

deny contains msg if {
	some budget_prefix in budget_prefixes
	some main_prefix in main_prefixes
	collides(budget_prefix, main_prefix)
	msg := sprintf("%s: the state prefix '%s' of the budget root collides with the one of gcp/tofu/ ('%s'); each root keeps its state in its own object", [label("state prefix"), budget_prefix, main_prefix])
}

# Identity of the main root: no base role and no role that writes budgets.
# Google's IAM page lists billing.resourcebudgets.write under roles/owner,
# roles/editor, roles/admin and roles/writer, and billing.budgets.create under
# roles/billing.costsManager and roles/billing.admin (RS-26). A role that is
# not written out cannot be checked, so it is refused too.

refused_roles := {
	"roles/owner",
	"roles/editor",
	"roles/admin",
	"roles/writer",
	"roles/billing.admin",
	"roles/billing.costsManager",
}

iam_blocks contains {"path": file.path, "address": address, "body": body} if {
	some file in tf_files
	some kind, prefix in {"resource": "", "data": "data."}
	some type, named in object.get(file.contents, kind, {})
	contains(type, "_iam_")
	some name, bodies in named
	some body in bodies
	address := sprintf("%s%s.%s", [prefix, type, name])
}

grants contains {"path": block.path, "address": block.address, "role": role} if {
	some block in iam_blocks
	role := block.body.role
}

grants contains {"path": block.path, "address": block.address, "role": role} if {
	some block in iam_blocks
	some binding in object.get(block.body, "binding", [])
	role := binding.role
}

deny contains msg if {
	some grant in grants
	grant.role in refused_roles
	msg := sprintf("%s: %s: %s grants %s; no identity of these roots holds a base role or a role that writes budgets (billing.budgets.* or billing.resourcebudgets.write)", [label("identity"), grant.path, grant.address, grant.role])
}

deny contains msg if {
	some grant in grants
	is_string(grant.role)
	contains(grant.role, "${")
	msg := sprintf("%s: %s: %s: role is not a literal (%s); S15 cannot show that it avoids the base roles and the budget roles", [label("identity"), grant.path, grant.address, grant.role])
}
