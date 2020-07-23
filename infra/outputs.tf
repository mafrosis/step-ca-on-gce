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

output gce_container_spec {
  value = module.vm_container.metadata_value
}
