# shellcheck shell=bash
# Names of what task up creates on the machine, and the kubeconfig of the
# project (spec 001, steps 6 and 7). Sourced by local/scripts/cluster.sh,
# mirror.sh and platform.sh, and by lib/preflight-checks.sh; S13 and S19
# read it too. Needs HOME.
#
# kind holds one cluster of a name per engine, and the engine one container
# and one volume of a name: these names are the project's on the machine.
# In phase 3 the project name becomes a variable of the blueprint.

# shellcheck disable=SC2034 # each script uses its own share of these values
{
  readonly CLUSTER_NAME="saas-b2b"
  # kind names the context of a cluster kind-<cluster>.
  readonly KUBE_CONTEXT="kind-$CLUSTER_NAME"
  # The label that kind puts on each node container of the cluster (kind
  # v0.33.0, pkg/cluster/internal/providers/docker/constants.go, line 21;
  # research RS-13): the preflight checks find the nodes by it.
  readonly NODE_LABEL="io.x-k8s.kind.cluster=$CLUSTER_NAME"
  # The network that kind creates for its nodes (kind v0.33.0,
  # pkg/cluster/internal/providers/docker/network.go, line 47); the mirror
  # joins it alone (ADR-011, condition 2).
  readonly KIND_NETWORK="kind"
  # The mirror container, whose name the hosts.toml files of
  # local/mirror/certs.d/ name, and its volume, one per project (ADR-011,
  # question 6).
  readonly MIRROR_CONTAINER="$CLUSTER_NAME-mirror"
  readonly MIRROR_VOLUME="$CLUSTER_NAME-mirror"
  # Label of the mirror container and of its volume. Docker asks for a key in
  # the reverse DNS of a domain one holds: the reserved domain of the built
  # images, saas-b2b.invalid (research RS-07, RS-13).
  readonly OWNER_LABEL_KEY="invalid.saas-b2b.role"
  readonly MIRROR_ROLE="registry-mirror"
  # Repository of the zot image; its tag and digest live in
  # local/tasks/local.yml, where Renovate reads them (ADR-016).
  readonly MIRROR_REPOSITORY="ghcr.io/project-zot/zot"
  # The kubeconfig of the project, outside the repository, readable by its
  # owner alone (research RS-21; ADR-004, condition 9). Every kubectl call
  # names it with the context above (S19).
  readonly KUBECONFIG_FILE="${HOME:?HOME is not set}/.kube/kind-$CLUSTER_NAME"
}

# kube ARG...: kubectl on the local cluster, and on it alone (FR-019).
kube() {
  kubectl --kubeconfig "$KUBECONFIG_FILE" --context "$KUBE_CONTEXT" "$@"
}
