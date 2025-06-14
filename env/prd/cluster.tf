locals {
  cluster_name = var.namespace

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
  vpc_uuid     = digitalocean_vpc.prd_vpc.id
  region       = var.region // Choose the appropriate region
  version      = data.digitalocean_kubernetes_versions.example.latest_version
  maintenance_policy {
    start_time = "04:00"
    day        = "sunday"
  }

  node_pool {
    name       = "pool-${var.namespace}"
    size       = "s-4vcpu-8gb" // Updated to a larger Droplet size
    auto_scale = true
    min_nodes  = 1
    max_nodes  = 3 // Adjust max nodes as needed
    tags       = concat(["${var.env}-worker-node", "pool-${var.namespace}"], values(local.tags))
  }

  tags = values(local.tags)
}

resource "kubernetes_namespace" "prd_fanclash" {
  metadata {
    name = var.namespace
  }
}
