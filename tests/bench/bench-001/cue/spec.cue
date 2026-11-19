// CELIAN project spec schema, CUE version (BENCH-001 trial).
// Usage: cue vet -c -d '#Spec' spec.cue ../yaml/valid.yaml
package celian

import "list"

#Target: "local" | "gcp"

#Spec: {
	specVersion: "0.1"
	project: {
		name:      =~"^[a-z][a-z0-9-]{1,38}[a-z0-9]$"
		blueprint: "saas-b2b"
	}
	targets: [...#Target] & list.MinItems(1) & list.UniqueItems()
	gcp?: {
		region: =~"^[a-z]+-[a-z]+[0-9]+$"
	}
	components: {
		database: "postgres"
		cache?:   "redis"
	}
	// A spec that targets gcp must give its region.
	if list.Contains(targets, "gcp") {
		gcp: region: string
	}
}
