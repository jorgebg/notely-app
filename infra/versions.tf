terraform {
  required_version = ">= 1.11"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  # The state lives in the foundation's bucket. A backend block can't use variables, so the
  # bucket name comes at init time: -backend-config="bucket=..."
  backend "gcs" {
    prefix = "notely"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
