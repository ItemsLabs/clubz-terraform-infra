resource "aws_route53_record" "lb_record" {
  zone_id = data.aws_route53_zone.gameon-app.zone_id
  name    = "livefantasy.gameon.app"
  type    = "A"
  ttl     = "300"
  records = [data.digitalocean_loadbalancer.ingress.ip]
}

data "aws_route53_zone" "gameon-app" {
  name = "gameon.app"
}

data "digitalocean_loadbalancer" "ingress" {  # change with the ingress load balancer number
  name = "afaca0bb30e76420ba04d24547d4afce"
}