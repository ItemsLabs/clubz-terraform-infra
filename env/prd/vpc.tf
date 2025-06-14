resource "digitalocean_vpc" "prd_vpc" {
  name     = "${var.env}-vpc"
  region   = var.region // Choose your region
  ip_range = "10.200.16.0/20"
}



