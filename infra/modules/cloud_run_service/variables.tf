variable "name" {
  type = string
}

variable "location" {
  type = string
}

variable "image" {
  description = "Image to run, ideally pinned by digest"
  type        = string
}

variable "env" {
  description = "Plain environment variables"
  type        = map(string)
  default     = {}
}

variable "max_instances" {
  type    = number
  default = 3
}

variable "service_account" {
  description = "E-mail of the identity the service runs as (null: the project's default)"
  type        = string
  default     = null
}

variable "ingress" {
  description = "INGRESS_TRAFFIC_ALL (internet) or INGRESS_TRAFFIC_INTERNAL_ONLY (only from our VPC)"
  type        = string
  default     = "INGRESS_TRAFFIC_ALL"
}

variable "vpc" {
  description = "Send outbound traffic into a VPC subnet (Direct VPC egress). null: no VPC."
  type = object({
    network    = string
    subnetwork = string
    egress     = string # ALL_TRAFFIC or PRIVATE_RANGES_ONLY
    tags       = optional(list(string), [])
  })
  default = null
}

variable "secret_env" {
  description = "Environment variables read from Secret Manager when an instance starts"
  type = map(object({
    secret  = string
    version = string
  }))
  default = {}
}
