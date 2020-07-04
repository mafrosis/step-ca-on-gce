variable region {
  description = "Default GCP region"
  type        = string
  default     = "australia-southeast1"
}

variable project_id {
  description = "GCP Project ID"
  type        = string
}

variable dns_zone {
  description = "The DNS zone predefined for services in this project"
  type        = string
}
