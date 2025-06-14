module "spaces" {
  for_each      = toset(var.public-space-names)
  source        = "terraform-do-modules/spaces/digitalocean"
  version       = "1.0.0"
  name          = each.key
  environment   = var.env
  acl           = "public-read"
  force_destroy = false
  region        = var.region
}