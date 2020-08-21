locals {
  gce_sa = format(
    "serviceAccount:%s", google_service_account.gce.email
  )

  # Allow GCE service account to ..
  gce_iam_roles = [
    # .. read public keys, sign and verify data
    "roles/cloudkms.signerVerifier",
    # .. pull from Container Registry
    "roles/storage.objectViewer",
    # .. read secret payload from Secrets Manager
    "roles/secretmanager.secretAccessor",
  ]
}

resource google_service_account gce {
  account_id   = "gce-sa"
  display_name = "SA for Step CA on GCE"
  project      = data.google_project.project.project_id
}

# Apply IAM roles to the project step-ca GCE VM service account
resource google_project_iam_member gce_roles {
  project = data.google_project.project.project_id
  count   = length(local.gce_iam_roles)
  role    = local.gce_iam_roles[count.index]
  member  = local.gce_sa
}

# Read/write on the Step CA DB backup bucket
resource google_storage_bucket_iam_member gce_storage_access {
  bucket = google_storage_bucket.step_db_backup.name
  role   = "roles/storage.objectAdmin"
  member = local.gce_sa
}
