# The images we pushed with docker, read from the foundation's registry. self_link pins the
# exact image by digest (…/notely-web@sha256:…), not by a tag that can move.
data "google_artifact_registry_docker_image" "web" {
  location      = var.region
  repository_id = local.app
  image_name    = "notely-web:demo"
}

data "google_artifact_registry_docker_image" "api" {
  location      = var.region
  repository_id = local.app
  image_name    = "notely-api:demo"
}
