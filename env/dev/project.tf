resource "digitalocean_project" "fanclash" {
  name        = "${var.project}-${var.env}"
  description = "Represent development resources for fanclash."
  purpose     = "Web Application"
  environment = "Development"
  resources = concat(
    [
      digitalocean_kubernetes_cluster.fanclash_cluster.urn,
      digitalocean_database_cluster.fanclash_cluster.urn,
      digitalocean_floating_ip.fanclash_floating_ip.urn
    ],
    [for space in module.spaces : space.urn]
  )
}
