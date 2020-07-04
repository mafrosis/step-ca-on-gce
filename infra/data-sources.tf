data google_project project {
  project_id = var.project_id
}

data google_kms_key_ring keyring {
  project  = var.project_id
  location = var.region
  name     = format("%s-keyring", data.google_project.project.name)
}

data google_service_account cloudrun {
  project    = var.project_id
  account_id = "cloudrun-sa"
}
