resource "digitalocean_project" "fanclash" {
  name        = "${var.project}-${var.env}"
  description = "Represent development resources for fanclash."
  purpose     = "Web Application"
  environment = "Production"
}

resource "digitalocean_project_resources" "fanclash" {
  project = digitalocean_project.fanclash.id
  resources = concat(
    [
      digitalocean_kubernetes_cluster.fanclash_cluster.urn,
      digitalocean_droplet.openvpn_instance.urn,
      digitalocean_database_cluster.fanclash_cluster.urn
    ]
#    [for space in module.spaces : space.urn] 
  )
}