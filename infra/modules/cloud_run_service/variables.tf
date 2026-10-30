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
