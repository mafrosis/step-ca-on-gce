# Resources nginx as mTLS proxy on Cloud Run
#
locals {
  cloudrun_sa = format(
    "serviceAccount:%s", google_service_account.cloudrun.email
  )

  # Allow cloudrun service account to ..
  cloudrun_iam_roles = [
    # .. access encrypted secrets
    "roles/secretmanager.secretAccessor",
    # .. use the VPC connector for private comms
    "roles/vpaccess.user",
  ]
}

# Create service account for runtime context of Cloud Run containers
resource google_service_account cloudrun {
  account_id   = "cloudrun"
  display_name = "SA for proxy container on Cloud Run"
  project      = data.google_project.project.project_id
}

# Apply IAM roles to the project for project's service account
resource google_project_iam_member cloudrun_roles {
  project = data.google_project.project.project_id
  count   = length(local.cloudrun_iam_roles)
  role    = local.cloudrun_iam_roles[count.index]
  member  = local.cloudrun_sa
}

resource random_id service_name_suffix {
  byte_length = 2
}

# Create Cloud Run service
resource google_cloud_run_service proxy {
  project  = data.google_project.project.project_id
  name     = format("home-assistant-proxy-%s", random_id.service_name_suffix.hex)
  location = var.region

  template {
    spec {
      containers {
        image = format("asia.gcr.io/%s/home-assistant-proxy", data.google_project.project.project_id)

        env {
          name = "PROJECT_ID"
          value = data.google_project.project.project_id
        }
      }

      service_account_name = google_service_account.cloudrun.email
    }

    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale"        = "1000"
        "run.googleapis.com/client-name"          = "cloud-console"
        "run.googleapis.com/vpc-access-connector" = google_vpc_access_connector.private_access.id
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [
    google_project_iam_member.cloudrun_roles
  ]
}

# Set GCP IAM to allow public access to the Cloud Run service
resource google_cloud_run_service_iam_member allUsers {
  project  = data.google_project.project.project_id
  location = google_cloud_run_service.proxy.location

  service  = google_cloud_run_service.proxy.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Add a private VPC connector to for private access from Cloud Run to Step CA on GCE
resource google_vpc_access_connector private_access {
  project = data.google_project.project.project_id
  region  = var.region
  network = data.google_compute_network.vpc.name

  name          = "step-ca-private-access"
  ip_cidr_range = "10.8.0.0/28"
}
