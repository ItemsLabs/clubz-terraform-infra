locals {
  cluster_name = "${var.env}-${var.namespace}"

  // Define any other local values you need for your configuration
  tags = {
    terraform = "true"
    namespace = var.namespace
    env       = var.env
  }
}

data "digitalocean_kubernetes_versions" "example" {
  version_prefix = "1.29."
}

// Add resources here. For example, if you're creating a Kubernetes cluster:
resource "digitalocean_kubernetes_cluster" "fanclash_cluster" {
  name         = local.cluster_name
  auto_upgrade = true
  vpc_uuid     = digitalocean_vpc.dev_vpc.id
  region       = var.region // Choose the appropriate region
  version      = data.digitalocean_kubernetes_versions.example.latest_version
  maintenance_policy {
    start_time = "04:00"
    day        = "sunday"
  }

  node_pool {
    name       = "pool-${var.env}-${var.namespace}"
    size       = "s-4vcpu-8gb" // Updated to a larger Droplet size
    auto_scale = true
    min_nodes  = 1
    max_nodes  = 3 // Adjust max nodes as needed
    tags       = concat(["worker-node", "pool-${var.env}-${var.namespace}"], values(local.tags))
  }

  tags = values(local.tags)
}

data "digitalocean_droplets" "fanclash_dev_droplets" {}

resource "digitalocean_floating_ip" "fanclash_floating_ip" {
  # Assuming there is only one match or you want the first match
  droplet_id = [for d in data.digitalocean_droplets.fanclash_dev_droplets.droplets : d.id if length(regexall("^pool-dev-fanclash-.*$", d.name)) > 0][0]
  region     = var.region
}
