# PLAN ONLY: what the database would look like as a managed service. Not applied in the demo:
# Cloud SQL has no free tier (~10 USD/month for the smallest instance, twice that with a
# standby) and takes ~12 minutes to create.

resource "google_project_service" "cloudsql" {
  for_each = toset(["sqladmin.googleapis.com", "servicenetworking.googleapis.com"])

  service            = each.value
  disable_on_destroy = false
}

# Cloud SQL runs in a network of Google's. "Private services access" reserves a range of our
# addresses for it and peers the two networks: the instance gets a private IP in our range.
resource "google_compute_global_address" "cloudsql" {
  name          = "${local.app}-cloudsql-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = data.google_compute_network.notely.id
}

resource "google_service_networking_connection" "cloudsql" {
  network                 = data.google_compute_network.notely.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.cloudsql.name]
  depends_on              = [google_project_service.cloudsql]
}

resource "google_sql_database_instance" "notely" {
  name                = "${local.app}-pg"
  database_version    = "POSTGRES_16"
  region              = var.region
  deletion_protection = true # what prevent_destroy did for our data disk, built in

  settings {
    edition           = "ENTERPRISE" # Enterprise Plus has no small shared-core machines
    tier              = "db-f1-micro"
    availability_type = "ZONAL" # REGIONAL adds a standby in another zone: high availability

    ip_configuration {
      ipv4_enabled    = false # no public address, like our VM
      private_network = data.google_compute_network.notely.id
    }

    # What we would otherwise build and run ourselves:
    backup_configuration {
      enabled                        = true # daily backups
      point_in_time_recovery_enabled = true # restore to any second of the last days
    }
    maintenance_window {
      day  = 7 # patching by Google, Sundays at 03:00
      hour = 3
    }
  }

  depends_on = [google_service_networking_connection.cloudsql]
}

resource "google_sql_database" "notely" {
  name     = local.app
  instance = google_sql_database_instance.notely.name
}

resource "google_sql_user" "notely" {
  name     = local.app
  instance = google_sql_database_instance.notely.name

  # Write-only, like the secret. The same ephemeral value reaches both only in an apply that
  # also bumps secret_data_wo_version: a real switch would rotate the password with it.
  password_wo         = ephemeral.random_password.db.result
  password_wo_version = 1
}
