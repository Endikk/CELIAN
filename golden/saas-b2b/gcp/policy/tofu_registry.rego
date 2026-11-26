# S15: the registry of the providers of the gcp layer (spec 001, FR-011;
# ADR-008, condition 7). Rules to come; this stub refuses nothing yet.
package tofu_registry

label := "S15 (FR-011; ADR-008, condition 7; research RS-16)"

deny contains msg if {
	false
	msg := label
}
