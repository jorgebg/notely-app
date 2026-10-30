# The API.
module "api" {
  source   = "./modules/cloud_run_service"
  name     = "${local.app}-api"
  location = var.region
  image    = data.google_artifact_registry_docker_image.api.self_link

  service_account = google_service_account.api.email
  ingress         = "INGRESS_TRAFFIC_INTERNAL_ONLY" # the internet gets a 404
  env = {
    ATTACHMENTS_BUCKET = google_storage_bucket.attachments.name
    DB_HOST            = google_compute_address.db.address
  }
  secret_env = {
    DB_PASSWORD = {
      secret  = google_secret_manager_secret.db_password.secret_id
      version = google_secret_manager_secret_version.db_password.version
    }
  }
  # Private addresses (the database) through our VPC, tagged so the firewall knows it.
  vpc = {
    network    = data.google_compute_network.notely.id
    subnetwork = data.google_compute_subnetwork.notely.id
    egress     = "PRIVATE_RANGES_ONLY"
    tags       = ["${local.app}-api"]
  }

  # Nothing above references the grant: without this, a revision could start before it may
  # read the secret.
  depends_on = [google_secret_manager_secret_iam_member.db_password]
}

# The page: serves the React page and forwards /api and /health to API_URL.
# (Two module calls, not for_each over a map: the page needs an output of the API.)
module "web" {
  source   = "./modules/cloud_run_service"
  name     = "${local.app}-web"
  location = var.region
  image    = data.google_artifact_registry_docker_image.web.self_link

  service_account = google_service_account.web.email
  env = {
    API_URL = module.api.uri
  }
  # Everything the page sends out goes through our network, so its calls to the API count
  # as internal.
  vpc = {
    network    = data.google_compute_network.notely.id
    subnetwork = data.google_compute_subnetwork.notely.id
    egress     = "ALL_TRAFFIC"
  }
}
