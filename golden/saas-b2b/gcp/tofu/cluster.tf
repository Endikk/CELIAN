# GKE Autopilot cluster (ADR-008, decision), private nodes, control plane
# reached by its DNS endpoint only, Regular channel (ADR-004, version rule),
# registered in a fleet for Config Sync (ADR-010). Attributes: research RS-16.

# ADR-008, condition 4: a dedicated account for the nodes, never the default
# account of Compute Engine, which may hold more permissions than GKE needs.
resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.name}-nodes"
  display_name = "GKE Autopilot nodes of ${var.name}"

  depends_on = [google_project_service.apis]
}

resource "google_project_iam_member" "nodes" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# Trivy finding justified (T109): AVD-GCP-0061 asks for master authorized
# networks, a list of CIDR ranges allowed on the IP endpoint of the control
# plane. That endpoint is disabled (ip_endpoints_config), so there is no IP
# access to restrict: the control plane answers on its DNS endpoint only,
# where IAM decides who connects (ADR-008, condition 5). Written by [OPS] on
# 2026-11-25, reviewed by [SECU] on 2026-11-25. S15 accepts this one ignore
# comment only, by a closed list. The comment stays right above the resource,
# where Trivy reads it.
#trivy:ignore:AVD-GCP-0061
resource "google_container_cluster" "main" {
  project          = var.project_id
  name             = var.name
  location         = var.region
  enable_autopilot = true

  # A minimum, not the running version: GKE upgrades the cluster within its
  # channel. A minor ("1.36") resolves to its highest valid patch. ADR-007,
  # condition 2, wants 1.35.5-gke.1163012 or later for the secret sync.
  min_master_version = local.platform.kubernetes_minor

  # ADR-008, condition 10: the documented teardown first lifts this
  # protection by an apply, then destroys. The user runs both, never an agent.
  deletion_protection = true

  network         = google_compute_network.main.id
  subnetwork      = google_compute_subnetwork.main.id
  resource_labels = local.labels

  release_channel {
    channel = "REGULAR"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes = true
  }

  # ADR-008, condition 5: written out, so that access to the control plane
  # depends on no implicit default. The DNS endpoint answers from any network
  # that reaches Google Cloud APIs, IAM deciding who connects; Google
  # recommends using it alone. External traffic is allowed so that the user
  # can apply the manifests of the layer from a workstation. Value proposed
  # by [OPS] on 2026-11-25, to be confirmed by [SECU].
  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic = true
      # Written false: no Kubernetes token or certificate authentication
      # through the DNS endpoint, IAM only. Argument names of the provider
      # page at v8.12.0, read on 2026-11-25; S15 (condition 5) refuses true
      # and an absent line.
      enable_k8s_tokens_via_dns = false
      enable_k8s_certs_via_dns  = false
    }

    ip_endpoints_config {
      enabled = false
    }
  }

  # ADR-008, condition 4: Autopilot creates the nodes under this account.
  cluster_autoscaling {
    auto_provisioning_defaults {
      service_account = google_service_account.nodes.email
    }
  }

  # ADR-005: the Gateway controller of GKE, standard channel of the CRDs. The
  # class of the Gateway is chosen with the manifests of step 14.
  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  # ADR-007: GKE syncs Secret Manager into Kubernetes Secrets. No rotation:
  # ADR-007, condition 2, would want an interval of 15 minutes at least for 3
  # secrets, and does not say whether a Secret follows a new version without
  # it (question left to the test of its condition 3).
  secret_sync_config {
    enabled = true
  }

  # ADR-010: Config Sync needs the cluster in a fleet (config_sync.tf).
  fleet {
    project = var.project_id
  }

  depends_on = [
    google_project_service.apis,
    google_project_iam_member.nodes,
  ]
}
