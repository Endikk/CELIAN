# S15: the budget root of the gcp layer (T110; ADR-008, question 1). Red stub:
# no rule yet, so that tofu_budget_test.rego and the cases of testdata/ compile
# and fail. The rules come in the next commit.
package tofu_budget

deny contains msg if {
	input == "no rule yet"
	msg := "red stub"
}
