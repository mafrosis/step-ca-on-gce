data google_project project {
  project_id = var.project_id
}

locals {
  # Extract the random suffix generated as part of GCP project creation
  # https://github.com/mafrosis/gcp-bootstrap/blob/dev/projects/modules/gcp-project/project.tf#L25
  project_random_suffix = strrev(substr(strrev(var.project_id), 0, 6))
}

data google_compute_network vpc {
  project = var.project_id
  name    = format("vpc-%s", local.project_random_suffix)
}

data google_compute_subnetwork subnet {
  project = var.project_id
  region  = var.region
  name    = format("subnet-%s-0", local.project_random_suffix)
}

data google_kms_key_ring keyring {
  project  = var.project_id
  location = var.region
  name     = format("%s-keyring", data.google_project.project.name)
}
