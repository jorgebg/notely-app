# Foundation: the long-lived layer. What must exist before the app, and outlive it.
# A separate configuration with its own (local) state: the app keeps its state in a bucket
# created here, and Terraform can't store its state in a bucket it is about to create.
# The app's `terraform destroy` leaves all of this; it costs nothing while idle.

terraform {
  required_version = ">= 1.11"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.7.0"
    }
  }
}

variable "project_id" {
  description = "Google Cloud project to deploy into"
  type        = string
}

variable "region" {
  description = "Region for every regional resource (us-central1: inside the free tier)"
  type        = string
  default     = "us-central1"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Every Google API the demo uses, switched on from code too.
resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "compute.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
    "monitoring.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false # other things in the project may use them too
}

# --- Where the app's Terraform state lives --------------------------------------------------------

resource "google_storage_bucket" "tfstate" {
  name                        = "${var.project_id}-tfstate"
  location                    = upper(var.region)
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true # a demo; in real life: false

  versioning {
    enabled = true # every apply keeps the previous state: an undo for the state file
  }

  depends_on = [google_project_service.apis]
}

# --- The network the app plugs into ---------------------------------------------------------------

# A private network of our own. A new VPC accepts no incoming connection until a firewall
# rule allows it.
resource "google_compute_network" "notely" {
  name                    = "notely"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.apis]
}

resource "google_compute_subnetwork" "notely" {
  name          = "notely-${var.region}"
  region        = var.region
  network       = google_compute_network.notely.id
  ip_cidr_range = "10.10.0.0/24"

  # Lets machines with no public address reach Google APIs (run.app, pkg.dev,
  # secretmanager...) through Google's own network.
  private_ip_google_access = true
}

# --- Where container images live ------------------------------------------------------------------

# Our images. Keep the two newest versions of each, delete the rest: stays in the free 0.5 GB.
resource "google_artifact_registry_repository" "notely" {
  repository_id = "notely"
  location      = var.region
  format        = "DOCKER"

  cleanup_policy_dry_run = false
  cleanup_policies {
    id     = "keep-two-newest"
    action = "KEEP"
    most_recent_versions {
      keep_count = 2
    }
  }
  cleanup_policies {
    id     = "delete-the-rest"
    action = "DELETE"
    condition {
      tag_state = "ANY"
    }
  }

  depends_on = [google_project_service.apis]
}

# Docker Hub, proxied by Artifact Registry: machines with no internet access can still pull
# public images (the database VM pulls postgres through it).
resource "google_artifact_registry_repository" "dockerhub" {
  repository_id = "dockerhub"
  location      = var.region
  format        = "DOCKER"
  mode          = "REMOTE_REPOSITORY"
  remote_repository_config {
    description = "Docker Hub"
    docker_repository {
      public_repository = "DOCKER_HUB"
    }
  }

  depends_on = [google_project_service.apis]
}

output "state_bucket" {
  value = google_storage_bucket.tfstate.name
}

output "registry" {
  description = "Prefix for docker tag / docker push"
  value       = google_artifact_registry_repository.notely.registry_uri
}
