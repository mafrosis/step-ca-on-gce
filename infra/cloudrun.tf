# Create resources to support using Cloud Run
#
locals {
  cloudrun_sa = format(
    "serviceAccount:%s",
    google_service_account.cloudrun.email,
  )

  # Allow cloudrun service account to ..
  cloudrun_iam_roles = [
    # .. read public keys, sign and verify data
    "roles/cloudkms.signerVerifier",
  ]
}

# Create service account for runtime context of Cloud Run containers
resource google_service_account cloudrun {
  account_id   = "cloudrun"
  display_name = "SA for Cloud Run runtime containers"
  project      = data.google_project.project.project_id
}

# Apply IAM roles to the project for project's service account
resource google_project_iam_member cloudrun_roles {
  project = data.google_project.project.project_id
  count   = length(local.cloudrun_iam_roles)
  role    = local.cloudrun_iam_roles[count.index]
  member  = local.cloudrun_sa
}

resource google_cloud_run_service step_ca {
  project  = data.google_project.project.project_id
  name     = "step-ca"
  location = "asia-northeast1"

  template {
    spec {
      containers {
        image = format("asia.gcr.io/%s/step-ca:stable", data.google_project.project.project_id)
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

resource google_cloud_run_service_iam_member allUsers {
  project  = data.google_project.project.project_id
  location = google_cloud_run_service.step_ca.location

  service  = google_cloud_run_service.step_ca.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
