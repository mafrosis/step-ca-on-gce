# Create DNS entry for the Smallstep CA server
#
# Lookup the project's DNS zone, which is created for us at project creation time
data google_dns_managed_zone project {
  project = data.google_project.project.project_id
  name    = var.dns_zone
}

resource google_dns_record_set cloudrun_cname {
  name         = "certs.${data.google_dns_managed_zone.project.dns_name}"
  project      = data.google_project.project.project_id
  managed_zone = data.google_dns_managed_zone.project.name
  type         = "CNAME"
  ttl          = 300
  rrdatas      = [
    "ghs.googlehosted.com.",
  ]
}

# Map the domain to our cloudrun service
resource google_cloud_run_domain_mapping default {
  project  = data.google_project.project.project_id
	name     = trimsuffix("certs.${data.google_dns_managed_zone.project.dns_name}", ".")
  location = google_cloud_run_service.step_ca.location

  metadata {
    namespace = data.google_project.project.project_id
  }

  spec {
    route_name     = google_cloud_run_service.step_ca.name
		force_override = true
  }
}
