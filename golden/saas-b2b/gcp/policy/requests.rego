# S16: the manifests of the gcp layer set `requests` on every pod, and the
# admission rule that refuses a pod without them is there (spec 001, plan,
# matrix S16; ADR-008, condition 9; research RS-16; R-05).
#
# Why: on Autopilot a container without requests is billed for the default
# of the platform, 0.5 vCPU and 2 GiB for a pod, 23.4 USD a month at the
# example prices of us-central1 that [FINOPS] read (ADR-008, condition 9).
# Two lines of defence, as the condition wants: the manifests set the
# requests, and a ValidatingAdmissionPolicy refuses the pod that has none,
# whoever creates it.
#
# - every container and init container of every pod template (Pod,
#   Deployment, StatefulSet, DaemonSet, ReplicaSet, Job, CronJob) in the
#   render sets requests.cpu and requests.memory;
# - one ValidatingAdmissionPolicy matches the creation of pods, fails closed
#   (failurePolicy: Fail) and its expressions read the requests of the
#   containers and of the init containers;
# - one ValidatingAdmissionPolicyBinding denies (validationActions: [Deny]
#   and nothing else) in the namespace of the application, chosen by the
#   label that Kubernetes puts on every namespace.
#
# Written against the objects of Kubernetes v1.36 (admissionregistration.k8s.io/v1,
# stable since v1.30; kubernetes.io/docs/reference/access-authn-authz/
# validating-admission-policy/, read on 2026-11-26). The CEL expression is
# not compiled here: no tool of the repo does it offline, and the API server
# does it at the first apply (E16 on kind, then GKE).
#
# Input: the render of gcp/k8s/prod given to `conftest test --combine`, one
# entry per YAML document with its `path` and parsed `contents`
# (tests/static/s16-requests.sh).
package requests

label := "S16 (FR-012; ADR-008, condition 9)"

controllers := {"Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "Job"}

objects contains [path, obj] if {
	some file in input
	path := file.path
	obj := file.contents
	is_object(obj)
}

describe(obj) := sprintf("%v %v", [object.get(obj, "kind", null), object.get(object.get(obj, "metadata", {}), "name", null)])

# The pod specs of the render, with the object they belong to.
pod_specs contains [path, obj, spec] if {
	some [path, obj] in objects
	obj.kind in controllers
	spec := obj.spec.template.spec
}

pod_specs contains [path, obj, spec] if {
	some [path, obj] in objects
	obj.kind == "CronJob"
	spec := obj.spec.jobTemplate.spec.template.spec
}

pod_specs contains [path, obj, spec] if {
	some [path, obj] in objects
	obj.kind == "Pod"
	spec := obj.spec
}

# Every container of a spec, init containers included, with its kind.
containers_of(spec) := array.concat(
	[{"kind": "container", "value": c} | some c in object.get(spec, "containers", [])],
	[{"kind": "init container", "value": c} | some c in object.get(spec, "initContainers", [])],
)

has_request(container, resource) if {
	value := container.resources.requests[resource]
	value != ""
	value != null
}

deny contains msg if {
	some [path, obj, spec] in pod_specs
	some entry in containers_of(spec)
	some resource in ["cpu", "memory"]
	not has_request(entry.value, resource)
	msg := sprintf("%s: %s, %s of %s %s, sets no requests.%s: Autopilot would bill the default of 0.5 vCPU and 2 GiB", [label, path, entry.kind, describe(obj), object.get(entry.value, "name", "?"), resource])
}

# --- The admission rule ----------------------------------------------------

policies contains [path, obj] if {
	some [path, obj] in objects
	obj.apiVersion == "admissionregistration.k8s.io/v1"
	obj.kind == "ValidatingAdmissionPolicy"
}

bindings contains [path, obj] if {
	some [path, obj] in objects
	obj.apiVersion == "admissionregistration.k8s.io/v1"
	obj.kind == "ValidatingAdmissionPolicyBinding"
}

app_namespaces contains name if {
	some [_, obj] in objects
	obj.kind == "Namespace"
	name := obj.metadata.name
}

matches_pod_creation(policy) if {
	some rule in policy.spec.matchConstraints.resourceRules
	"" in rule.apiGroups
	"pods" in rule.resources
	"CREATE" in rule.operations
}

# The words a CEL expression has to read to check the requests of every
# container and init container.
reads_requests(policy) if {
	count(policy.spec.validations) > 0
	every validation in policy.spec.validations {
		expression := validation.expression
		contains(expression, "requests")
		contains(expression, "cpu")
		contains(expression, "memory")
		contains(expression, "containers")
		contains(expression, "initContainers")
	}
}

deny contains msg if {
	count(policies) == 0
	msg := sprintf("%s: no ValidatingAdmissionPolicy in the render: nothing refuses a pod without requests (ADR-008, condition 9)", [label])
}

deny contains msg if {
	some [path, policy] in policies
	not matches_pod_creation(policy)
	msg := sprintf("%s: %s, %s does not match the CREATE of pods (apiGroups [\"\"], resources [\"pods\"])", [label, path, describe(policy)])
}

# Written Fail, never left to a default and never Ignore: a rule that fails
# open would let a pod without requests through.
deny contains msg if {
	some [path, policy] in policies
	not policy.spec.failurePolicy == "Fail"
	msg := sprintf("%s: %s, %s has failurePolicy %v: write Fail, which refuses the pod when the rule itself fails", [label, path, describe(policy), object.get(policy.spec, "failurePolicy", "unset")])
}

deny contains msg if {
	some [path, policy] in policies
	not reads_requests(policy)
	msg := sprintf("%s: %s, %s has no validation that reads requests.cpu and requests.memory of containers and initContainers", [label, path, describe(policy)])
}

deny contains msg if {
	count(policies) > 0
	count(bindings) == 0
	msg := sprintf("%s: a ValidatingAdmissionPolicy has no ValidatingAdmissionPolicyBinding: it refuses nothing without one", [label])
}

deny contains msg if {
	some [path, binding] in bindings
	not binding.spec.policyName in {policy.metadata.name | some [_, policy] in policies}
	msg := sprintf("%s: %s, %s names the policy %v, which is not in the render", [label, path, describe(binding), binding.spec.policyName])
}

deny contains msg if {
	some [path, binding] in bindings
	binding.spec.validationActions != ["Deny"]
	msg := sprintf("%s: %s, %s has validationActions %v: Deny alone refuses the pod; Warn and Audit let it through", [label, path, describe(binding), binding.spec.validationActions])
}

# The namespace a binding selects by the label of every namespace, "" if none.
bound_namespace(binding) := object.get(object.get(object.get(object.get(binding.spec, "matchResources", {}), "namespaceSelector", {}), "matchLabels", {}), "kubernetes.io/metadata.name", "")

deny contains msg if {
	some [path, binding] in bindings
	not bound_namespace(binding) in app_namespaces
	msg := sprintf("%s: %s, %s selects no namespace of the application by kubernetes.io/metadata.name (namespaces of the render: %v)", [label, path, describe(binding), app_namespaces])
}
