variable "project_id" {
  description = "Google Cloud project to deploy into"
  type        = string
}

variable "region" {
  description = "Region for every regional resource (us-central1: inside the free tier)"
  type        = string
  default     = "us-central1"
}

locals {
  app = "notely" # prefix of every name
}
