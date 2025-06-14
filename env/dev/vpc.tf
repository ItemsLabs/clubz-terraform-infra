resource "digitalocean_vpc" "dev_vpc" {
  name     = "${var.env}-vpc"
  region   = var.region // Choose your region
  ip_range = "10.200.0.0/20"
}



