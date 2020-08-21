output network {
  value = data.google_compute_network.vpc.self_link
}

output subnet {
  value = data.google_compute_subnetwork.subnet.self_link
}

output managed_instance_group {
  value = google_compute_instance_group_manager.mig.name
}

output gce_external_ip {
  value = google_compute_address.static.address
}

output gce_service_account {
  value = google_service_account.gce.email
}

output gce_container_spec {
  value = module.vm_container.metadata_value
}

output cloudrun_service_account {
  value = google_service_account.cloudrun.email
}

output cloudrun_spec {
  value = google_cloud_run_service.proxy.status
}

output db_backup_bucket {
  value = google_storage_bucket.step_db_backup.name
}
