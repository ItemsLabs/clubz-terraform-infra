locals {
  do_common_tags = [
    "Environment:${var.env}",
    "Owner:${var.company}",
    "Project:${var.project}",
    "Terraform:true"
  ]
}

resource "digitalocean_droplet" "openvpn_instance" {
  // Example configuration, adjust based on your needs
  name     = "openvpnaccessserver2113onubuntu2204-s-1vcpu-1gb-ams3-01"
  size     = "s-1vcpu-1gb"
  image    = "openvpn-18-04"
  region   = var.region
  vpc_uuid = digitalocean_vpc.dev_vpc.id
  ssh_keys = [41251010]
  tags     = local.do_common_tags
  // ... other configurations ...
}


output "openvpn_server_public_ip" {
  value = digitalocean_droplet.openvpn_instance.ipv4_address
}
