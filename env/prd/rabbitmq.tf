resource "kubectl_manifest" "rabbitmq_namespace" {
  yaml_body = <<-EOT
    apiVersion: v1
    kind: Namespace
    metadata:
      name: rabbitmq-system
  EOT

}

resource "helm_release" "rabbitmq" {
  name       = "rabbitmq-cluster"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "rabbitmq"
  namespace  = "rabbitmq-system"
  version    = "12.10.0"
  depends_on = [
    kubectl_manifest.rabbitmq_namespace
  ]
  # set {
  #   name  = "auth.username"
  #   value = "rabbitmq"
  # }

  # set {
  #   name  = "auth.password"
  #   value = "Qp,2Sv_^!6#}J@=U"
  # }
  set {
    name  = "replicaCount"
    value = "2"
  }
  set {
    name  = "persistence.storageClass"
    value = "do-block-storage"
  }
  set {
    name  = "persistence.size"
    value = "10Gi"
  }
  set {
    name  = "resources.requests.cpu"
    value = "1000m"
  }

  set {
    name  = "resources.requests.memory"
    value = "2Gi"
  }
  set {
    name  = "resources.limits.cpu"
    value = "1000m"
  }
  set {
    name  = "resources.limits.memory"
    value = "2Gi"
  }
}

