# Tests of S16 (requests.rego), run by `conftest verify`.
package requests

namespace := {
	"apiVersion": "v1",
	"kind": "Namespace",
	"metadata": {"name": "saas-b2b"},
}

expression := concat(" && ", [
	"object.spec.containers.all(c, has(c.resources) && has(c.resources.requests) && 'cpu' in c.resources.requests && 'memory' in c.resources.requests)",
	"(!has(object.spec.initContainers) || object.spec.initContainers.all(c, has(c.resources) && has(c.resources.requests) && 'cpu' in c.resources.requests && 'memory' in c.resources.requests))",
])

policy := {
	"apiVersion": "admissionregistration.k8s.io/v1",
	"kind": "ValidatingAdmissionPolicy",
	"metadata": {"name": "require-requests"},
	"spec": {
		"failurePolicy": "Fail",
		"matchConstraints": {"resourceRules": [{
			"apiGroups": [""],
			"apiVersions": ["v1"],
			"operations": ["CREATE"],
			"resources": ["pods"],
		}]},
		"validations": [{"expression": expression, "message": "every container sets requests.cpu and requests.memory"}],
	},
}

binding := {
	"apiVersion": "admissionregistration.k8s.io/v1",
	"kind": "ValidatingAdmissionPolicyBinding",
	"metadata": {"name": "require-requests"},
	"spec": {
		"policyName": "require-requests",
		"validationActions": ["Deny"],
		"matchResources": {"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": "saas-b2b"}}},
	},
}

resources := {"requests": {"cpu": "100m", "memory": "128Mi"}}

deployment(spec) := {
	"apiVersion": "apps/v1",
	"kind": "Deployment",
	"metadata": {"name": "api", "namespace": "saas-b2b"},
	"spec": {"template": {"spec": spec}},
}

valid_deployment := deployment({
	"initContainers": [{"name": "wait", "image": "x", "resources": resources}],
	"containers": [{"name": "api", "image": "x", "resources": resources}],
})

valid_objects := [namespace, policy, binding, valid_deployment]

files(objs) := [{"path": "render.yaml", "contents": obj} | some obj in objs]

accepted(objs) if {
	msgs := deny with input as files(objs)
	count(msgs) == 0
}

denied_with(objs, fragment) if {
	msgs := deny with input as files(objs)
	some msg in msgs
	contains(msg, fragment)
}

test_s16_accepts_the_valid_render if {
	accepted(valid_objects)
}

test_s16_accepts_a_render_without_a_pod if {
	accepted([namespace, policy, binding])
}

test_s16_rejects_a_container_without_requests if {
	bad := deployment({"containers": [{"name": "api", "image": "x"}]})
	denied_with([namespace, policy, binding, bad], "sets no requests.cpu")
}

test_s16_rejects_a_container_without_memory if {
	bad := deployment({"containers": [{"name": "api", "image": "x", "resources": {"requests": {"cpu": "100m"}}}]})
	denied_with([namespace, policy, binding, bad], "sets no requests.memory")
}

test_s16_rejects_limits_without_requests if {
	bad := deployment({"containers": [{"name": "api", "image": "x", "resources": {"limits": {"cpu": "1", "memory": "1Gi"}}}]})
	denied_with([namespace, policy, binding, bad], "sets no requests.cpu")
}

test_s16_rejects_an_init_container_without_requests if {
	bad := deployment({
		"initContainers": [{"name": "wait", "image": "x"}],
		"containers": [{"name": "api", "image": "x", "resources": resources}],
	})
	denied_with([namespace, policy, binding, bad], "init container of Deployment api")
}

test_s16_rejects_a_cron_job_without_requests if {
	cron := {
		"apiVersion": "batch/v1",
		"kind": "CronJob",
		"metadata": {"name": "tick"},
		"spec": {"jobTemplate": {"spec": {"template": {"spec": {"containers": [{"name": "t", "image": "x"}]}}}}},
	}
	denied_with([namespace, policy, binding, cron], "CronJob tick")
}

test_s16_rejects_a_bare_pod_without_requests if {
	pod := {
		"apiVersion": "v1",
		"kind": "Pod",
		"metadata": {"name": "p"},
		"spec": {"containers": [{"name": "t", "image": "x"}]},
	}
	denied_with([namespace, policy, binding, pod], "Pod p")
}

test_s16_rejects_a_render_without_the_admission_rule if {
	denied_with([namespace, valid_deployment], "no ValidatingAdmissionPolicy")
}

test_s16_rejects_a_policy_that_ignores_pods if {
	bad := json.patch(policy, [{"op": "replace", "path": "/spec/matchConstraints/resourceRules/0/resources", "value": ["deployments"]}])
	denied_with([namespace, bad, binding], "does not match the CREATE of pods")
}

test_s16_rejects_a_policy_that_ignores_creation if {
	bad := json.patch(policy, [{"op": "replace", "path": "/spec/matchConstraints/resourceRules/0/operations", "value": ["UPDATE"]}])
	denied_with([namespace, bad, binding], "does not match the CREATE of pods")
}

test_s16_rejects_a_policy_that_fails_open if {
	bad := json.patch(policy, [{"op": "replace", "path": "/spec/failurePolicy", "value": "Ignore"}])
	denied_with([namespace, bad, binding], "has failurePolicy Ignore")
}

test_s16_rejects_a_policy_without_failure_policy if {
	bad := json.patch(policy, [{"op": "remove", "path": "/spec/failurePolicy"}])
	denied_with([namespace, bad, binding], "failurePolicy unset")
}

test_s16_rejects_a_policy_that_never_reads_requests if {
	bad := json.patch(policy, [{"op": "replace", "path": "/spec/validations/0/expression", "value": "true"}])
	denied_with([namespace, bad, binding], "no validation that reads requests")
}

test_s16_rejects_a_policy_that_skips_init_containers if {
	bad := json.patch(policy, [{"op": "replace", "path": "/spec/validations/0/expression", "value": "object.spec.containers.all(c, 'cpu' in c.resources.requests && 'memory' in c.resources.requests)"}])
	denied_with([namespace, bad, binding], "no validation that reads requests")
}

test_s16_rejects_a_policy_without_validations if {
	bad := json.patch(policy, [{"op": "remove", "path": "/spec/validations"}])
	denied_with([namespace, bad, binding], "no validation that reads requests")
}

test_s16_rejects_a_policy_without_binding if {
	denied_with([namespace, policy, valid_deployment], "has no ValidatingAdmissionPolicyBinding")
}

test_s16_rejects_a_binding_to_another_policy if {
	bad := json.patch(binding, [{"op": "replace", "path": "/spec/policyName", "value": "other"}])
	denied_with([namespace, policy, bad], "names the policy other")
}

test_s16_rejects_a_warn_only_binding if {
	bad := json.patch(binding, [{"op": "replace", "path": "/spec/validationActions", "value": ["Warn"]}])
	denied_with([namespace, policy, bad], "validationActions [\"Warn\"]")
}

test_s16_rejects_a_deny_and_audit_binding if {
	bad := json.patch(binding, [{"op": "replace", "path": "/spec/validationActions", "value": ["Deny", "Audit"]}])
	denied_with([namespace, policy, bad], "validationActions")
}

test_s16_rejects_a_binding_to_another_namespace if {
	bad := json.patch(binding, [{"op": "replace", "path": "/spec/matchResources/namespaceSelector/matchLabels/kubernetes.io~1metadata.name", "value": "kube-system"}])
	denied_with([namespace, policy, bad], "selects no namespace of the application")
}

test_s16_rejects_a_binding_for_every_namespace if {
	bad := json.patch(binding, [{"op": "remove", "path": "/spec/matchResources"}])
	denied_with([namespace, policy, bad], "selects no namespace of the application")
}
