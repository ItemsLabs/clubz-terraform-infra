variable "env" {
  description = "The environment (e.g., 'staging', 'production')"
  default     = "dev"
}

variable "company" {
  description = "The name of the company"
  default     = "gameon"
}

variable "region" {
  description = "The region (e.g., 'ams3', 'lon1')"
  default     = "ams3"
}

variable "namespace" {
  description = "Namespace for the project, used for naming resources"
  default     = "dev-clubz"
}

variable "root_domain_name" {
  description = "The root domain name for the project"
  default     = "clubz.dev"
}

variable "ssh_public_key" {
  description = "Public SSH key for accessing Droplets"
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFsCXa8jvBRjf9Pq7WGUIe2Ct8tSs0YijT5OxTL9hsCK pc@Muharrems-MacBook-Pro.local"
}

variable "ssh_public_key_openvpn" {
  description = "Public SSH key for accessing openvpn"
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAiazv8TqhSxO7agkShN/M/cOtgcM7G6DtZZdJPmnaey pc@Muharrems-MacBook-Pro.local"
}

variable "project" {
  description = "The name for the project"
  default     = "clubz"
}

variable "aws_region" {
  description = "The region of the project"
  default     = "us-east-1"
}

variable "storage_size_mib" {
  description = "The size of the db"
  default     = 61440
}

variable "public-space-names" {
  type        = list(string)
  description = "The name of the public spaces name"
  default = [
    "clubz-user-avatars",
    "clubz-team-crests",
    "clubz-player-images",
    "clubz-opta-feeds",
  "do-kubernetes-database-backups", ]
}


variable "do_token" {
  type        = string
  description = "DigitalOcean API token - set via TF_VAR_do_token environment variable"
}

variable "do_spaces_access_id" {
  type        = string
  description = "DigitalOcean Spaces access key - set via TF_VAR_do_spaces_access_id environment variable"
}

variable "do_spaces_secret_key" {
  type        = string
  description = "DigitalOcean Spaces secret key - set via TF_VAR_do_spaces_secret_key environment variable"
  sensitive   = true
}

# variable "gorush_image" {
#   description = "Docker image for Gorush"
#   type        = string
#   default     = "appleboy/gorush:1.17.1"
# }

# variable "gorush_replicas" {
#   description = "Number of replicas for Gorush deployment"
#   type        = number
#   default     = 1
# }