# terraform-google-container-vm module generates the metadata for our VM instance template
module vm_container {
  source = "github.com/terraform-google-modules/terraform-google-container-vm?ref=v2.0.0"

  container = {
    image = format("asia.gcr.io/%s/step-ca", data.google_project.project.project_id)
  }

  restart_policy = "Always"
}


data google_compute_image image_family {
  project = "cos-cloud"
  family  = "cos-stable"
}

resource google_compute_address static {
  project = data.google_project.project.project_id
  region  = var.region
  name    = "step-ca-vm"
}

resource google_compute_instance_template tpl {
  region   = var.region
  project  = data.google_project.project.project_id

  machine_type = "e2-micro"
  metadata     = {
    gce-container-declaration: module.vm_container.metadata_value
  }

  disk {
    source_image = data.google_compute_image.image_family.self_link
    disk_size_gb = 10
    disk_type    = "pd-standard"
    auto_delete  = true
    boot         = true
  }

  scheduling {
    preemptible = true

    # scheduling must have automatic_restart be false when preemptible is true
    automatic_restart = false
  }

  network_interface {
    subnetwork         = data.google_compute_subnetwork.subnet.self_link
    subnetwork_project = data.google_project.project.project_id

    access_config {
      nat_ip = google_compute_address.static.address
    }
  }

  labels = {
    "cos" = module.vm_container.vm_container_label
  }

  service_account {
		email = data.google_service_account.gce.email

    # full API to cloud, access is limited via IAM role
    # https://cloud.google.com/compute/docs/access/create-enable-service-accounts-for-instances#best_practices
    scopes = ["cloud-platform"]
  }

  lifecycle {
    # required to ensure no errors if the template is re-created
    # https://www.terraform.io/docs/providers/google/r/compute_instance_template.html#using-with-instance-group-manager
    create_before_destroy = true
  }
}


resource google_compute_instance_group_manager mig {
  provider = google-beta

  base_instance_name = "ca"
  project            = data.google_project.project.project_id

  version {
    instance_template = google_compute_instance_template.tpl.self_link
  }

  name        = "ca-mig"
  zone        = format("%s-c", var.region)
  target_size = 1

  named_port {
    name = "https"
    port = 443
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.autohealing.id
    initial_delay_sec = 300
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource google_compute_health_check autohealing {
  project = data.google_project.project.project_id
  name    = "ca-healthcheck"

  check_interval_sec  = 60
  timeout_sec         = 2
  healthy_threshold   = 3
  unhealthy_threshold = 10 # 50 seconds

  https_health_check {
    port         = 443
    request_path = "/health"
  }
}

resource google_compute_autoscaler autoscaling {
  project = data.google_project.project.project_id
  name    = "always-up"
  zone    = format("%s-c", var.region)
  target  = google_compute_instance_group_manager.mig.id

  autoscaling_policy {
    max_replicas    = 1
    min_replicas    = 1
    cooldown_period = 30

    cpu_utilization {
      target = 1.0
    }
  }
}
