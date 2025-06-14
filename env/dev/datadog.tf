# resource "helm_release" "datadog" {
#   name       = "datadog"
#   chart      = "datadog/datadog"
#   version    = "3.7.3" # Use the latest version suitable for your needs
#   values     = [file("${path.module}/datadog-values.yaml")]
#   repository = "https://helm.datadoghq.com"
#   create_namespace = true
#   namespace        = "datadog"
# }