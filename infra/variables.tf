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

variable "alert_email" {
  description = "Where alerts are sent"
  type        = string
}

variable "notification_channel" {
  description = "The e-mail channel created by hand in the console: projects/<id>/notificationChannels/<number>"
  type        = string
}
