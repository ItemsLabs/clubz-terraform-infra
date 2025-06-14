
resource "digitalocean_database_cluster" "fanclash_cluster" {
  name                 = "${var.project}-postgres-cluster-${var.env}"
  engine               = "pg"
  version              = "15"
  size                 = "db-s-4vcpu-8gb"
  storage_size_mib     = var.storage_size_mib
  region               = var.region
  private_network_uuid = digitalocean_vpc.prd_vpc.id
  node_count           = 1
  maintenance_window {
    hour = "02:00:00"
    day  = "saturday"
  }
}

resource "digitalocean_database_db" "fanclash" {
  cluster_id = digitalocean_database_cluster.fanclash_cluster.id
  name       = "fanclash"
}

resource "digitalocean_database_user" "root_user" {
  cluster_id = digitalocean_database_cluster.fanclash_cluster.id
  name       = "root"
}

resource "digitalocean_database_firewall" "postgres_firewall" {
  cluster_id = digitalocean_database_cluster.fanclash_cluster.id

  rule {
    type  = "k8s"
    value = digitalocean_kubernetes_cluster.fanclash_cluster.id
  }

  # Add this new rule block for the OpenVPN droplet
  rule {
    type  = "droplet"
    value = digitalocean_droplet.openvpn_instance.id
  }
  # Below three rules for snapshooter backups ips
  rule {
    type  = "ip_addr"
    value = "174.138.101.117"
  }

  rule {
    type  = "ip_addr"
    value = "143.198.240.52"
  }

  rule {
    type  = "ip_addr"
    value = "138.68.117.142"
  }
}

