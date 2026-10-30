# One Cloud Run service that anyone may call, scaling from zero.
resource "google_cloud_run_v2_service" "this" {
  name                = var.name
  location            = var.location
  deletion_protection = false # the demo ends with terraform destroy

  template {
    # Zero or one vpc_access block, depending on var.vpc: an optional block.
    dynamic "vpc_access" {
      for_each = var.vpc == null ? [] : [var.vpc]
      content {
        egress = vpc_access.value.egress
        network_interfaces {
          network    = vpc_access.value.network
          subnetwork = vpc_access.value.subnetwork
          tags       = vpc_access.value.tags
        }
      }
    }

    scaling {
      min_instance_count = 0 # scale to zero: free when nobody uses it
      max_instance_count = var.max_instances
    }

    containers {
      image = var.image

      # One env block per entry of the map.
      dynamic "env" {
        for_each = var.env
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "invoker" {
  name     = google_cloud_run_v2_service.this.name
  location = google_cloud_run_v2_service.this.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
