resource "helm_release" "redis" {
  name       = "redis"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "redis"
  namespace  = "${var.namespace}-${var.env}"
  version    = "18.12.0" # Specify the desired version of the Redis chart

}