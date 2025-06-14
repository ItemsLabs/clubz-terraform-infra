# resource "aws_route53_record" "lb_record" {
#   zone_id = data.aws_route53_zone.gamebuild_co.zone_id
#   name    = "laliga.gamebuild.co"
#   type    = "A"
#   ttl     = "300"
#   records = [data.digitalocean_loadbalancer.ingress.ip]
# }

# data "aws_route53_zone" "gamebuild_co" {
#   name = "gamebuild.co"
# }

# data "digitalocean_loadbalancer" "ingress" {
#   name = "a86c9101197754328bcb6372b31313d9"
# }

resource "digitalocean_record" "lb_record" {
  domain = "gamebuild.co"
  name   = "livefantasy"   # Subdomain
  type   = "A"
  ttl    = 300
  value  = data.digitalocean_loadbalancer.ingress.ip
}

data "digitalocean_domain" "gameon-app" {
  name = "gamebuild.co"
}

data "digitalocean_loadbalancer" "ingress" {
  name = "afaca0bb30e76420ba04d24547d4afce" # Change this to your actual load balancer name or ID
}