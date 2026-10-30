# The API.
module "api" {
  source   = "./modules/cloud_run_service"
  name     = "${local.app}-api"
  location = var.region
  image    = data.google_artifact_registry_docker_image.api.self_link
}

# The page: serves the React page and forwards /api and /health to API_URL.
# (Two module calls, not for_each over a map: the page needs an output of the API.)
module "web" {
  source   = "./modules/cloud_run_service"
  name     = "${local.app}-web"
  location = var.region
  image    = data.google_artifact_registry_docker_image.web.self_link
  env = {
    API_URL = module.api.uri
  }
  # Everything the page sends out goes through our network. Nothing changes yet; in the
  # next chunk it is how the page still reaches the API once the API is closed.
  vpc = {
    network    = data.google_compute_network.notely.id
    subnetwork = data.google_compute_subnetwork.notely.id
    egress     = "ALL_TRAFFIC"
  }
}
