resource google_storage_bucket step_db_backup {
  name     = format("%s-db-backup", data.google_project.project.project_id)
  project  = data.google_project.project.project_id
  location = var.region

  # delete the bucket even if it contains files
  force_destroy = true

  versioning {
    enabled = false
  }
}
