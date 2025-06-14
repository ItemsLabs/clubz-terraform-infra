resource "digitalocean_container_registry" "this" {
  name                   = "${var.company}-${var.region}"
  subscription_tier_slug = "professional"
  region                 = var.region
}


# data "digitalocean_container_registry_docker_credentials" "gameon_ams_registry_creds" {
#   registry_name = digitalocean_container_registry.gameon_ams3.name
#   write         = true
# }

# not like aws. one registery is created and image repos are created wiht docker push command.