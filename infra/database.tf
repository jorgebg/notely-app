# PostgreSQL 16 in a container on a small VM (e2-micro: inside the free tier).
# The VM is disposable; the data lives on its own disk.

locals {
  zone = "${var.region}-a"
  # Docker Hub through the foundation's proxy registry: the VM has no internet access.
  dockerhub = "projects/${var.project_id}/locations/${var.region}/repositories/dockerhub"
  db_image  = "${var.region}-docker.pkg.dev/${var.project_id}/dockerhub/library/postgres:16-alpine"
}

# --- The password ------------------------------------------------------------------------------

# Ephemeral: generated during plan/apply and never written to the state.
ephemeral "random_password" "db" {
  length  = 32
  special = false
}

resource "google_secret_manager_secret" "db_password" {
  secret_id = "${local.app}-db-password"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret = google_secret_manager_secret.db_password.id

  # Write-only: sent to Google, never stored in the state. Terraform only sends it when
  # the version number changes: bump it to rotate the password.
  secret_data_wo         = ephemeral.random_password.db.result
  secret_data_wo_version = 1
}

# --- The VM's identity and what it may read ------------------------------------------------------

resource "google_service_account" "db" {
  account_id   = "${local.app}-db"
  display_name = "Notely database VM"
}

resource "google_secret_manager_secret_iam_member" "db_password" {
  for_each = {
    db  = google_service_account.db.member
    api = google_service_account.api.member
  }
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value
}

resource "google_artifact_registry_repository_iam_member" "db_pull" {
  repository = local.dockerhub
  location   = var.region
  role       = "roles/artifactregistry.reader"
  member     = google_service_account.db.member
}

resource "google_project_iam_member" "db_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = google_service_account.db.member
}

# --- The VM, its address and its disk ------------------------------------------------------------

# A fixed private address: the API's DB_HOST survives replacing the VM.
resource "google_compute_address" "db" {
  name         = "${local.app}-db"
  region       = var.region
  subnetwork   = data.google_compute_subnetwork.notely.id
  address_type = "INTERNAL"
}

resource "google_compute_disk" "db_data" {
  name = "${local.app}-db-data"
  zone = local.zone
  type = "pd-standard" # the free tier covers 30 GB of standard disk
  size = 10
  # prevent_destroy removed: the session is over, everything goes.
}

resource "google_compute_instance" "db" {
  name                      = "${local.app}-db"
  zone                      = local.zone
  machine_type              = "e2-micro"
  tags                      = ["${local.app}-db"]
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
      type  = "pd-standard"
      size  = 10
    }
  }

  attached_disk {
    source      = google_compute_disk.db_data.id
    device_name = "pgdata"
  }

  # No access_config block: no public IP address.
  network_interface {
    subnetwork = data.google_compute_subnetwork.notely.id
    network_ip = google_compute_address.db.address
  }

  service_account {
    email  = google_service_account.db.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    user-data = templatefile("${path.module}/db-cloud-init.yaml", {
      secret        = google_secret_manager_secret.db_password.id
      registry_host = "${var.region}-docker.pkg.dev"
      image         = local.db_image
    })
    google-logging-enabled = "true"
  }

  # A new password means a new VM: it reads the password at boot. The data disk stays.
  lifecycle {
    replace_triggered_by = [google_secret_manager_secret_version.db_password]
  }

  depends_on = [
    google_secret_manager_secret_version.db_password,
    google_secret_manager_secret_iam_member.db_password,
    google_artifact_registry_repository_iam_member.db_pull,
  ]
}

# Only the API may open a connection to PostgreSQL. Everything else is denied by default.
resource "google_compute_firewall" "api_to_db" {
  name        = "${local.app}-api-to-db"
  network     = data.google_compute_network.notely.id
  direction   = "INGRESS"
  source_tags = ["${local.app}-api"]
  target_tags = ["${local.app}-db"]
  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }
}
