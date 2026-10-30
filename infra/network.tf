# The network belongs to the foundation (bootstrap/). Here we only look it up: a data source
# reads something this configuration doesn't manage.
data "google_compute_network" "notely" {
  name = local.app
}

data "google_compute_subnetwork" "notely" {
  name   = "${local.app}-${var.region}"
  region = var.region
}
