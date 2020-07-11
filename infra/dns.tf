# Create DNS entry for the Smallstep CA server
#
# Lookup the project's DNS zone, which is created for us at project creation time
data google_dns_managed_zone project {
  project = data.google_project.project.project_id
  name    = var.dns_zone
}

resource google_dns_record_set certs_a {
  name         = "certs.${data.google_dns_managed_zone.project.dns_name}"
  project      = data.google_project.project.project_id
  managed_zone = data.google_dns_managed_zone.project.name
  type         = "A"
  ttl          = 300

  rrdatas      = [
    google_compute_address.static.address
  ]
}
