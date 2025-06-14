#create nginx-ingress controller
resource "helm_release" "ingress-nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.9.0"

  depends_on = [
    helm_release.cert-manager,
    kubectl_manifest.cert_manager_clusterissuer
  ]
}

#creates cert-manager
resource "helm_release" "cert-manager" {
  name             = "cert-manager"
  namespace        = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  create_namespace = true
  version          = "1.14.2"

  values = [
    file("../../deploy-yml/cert-manager-values.yaml")
  ]

  set {
    name  = "startupapicheck.timeout"
    value = "5m"
  }
  set {
    name  = "installCRDs"
    value = true
  }
}

data "kubectl_path_documents" "cert_manager_clusterissuer_yaml" {
  pattern = "../../deploy-yml/letsencrypt-prod-1.6+.yaml"
}

resource "kubectl_manifest" "cert_manager_clusterissuer" {
  count     = length(data.kubectl_path_documents.cert_manager_clusterissuer_yaml.documents)
  yaml_body = element(data.kubectl_path_documents.cert_manager_clusterissuer_yaml.documents, count.index)
  depends_on = [
    helm_release.cert-manager
  ]
}

resource "kubernetes_manifest" "ingress" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "fanclash-ingress"
      namespace = "fanclash-dev"
      annotations = {
        "kubernetes.io/ingress.class"    = "nginx"
        "kubernetes.io/tls-acme"         = "true"
        "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
      }
    }
    spec = {
      ingressClassName = "nginx"
      rules = [
        {
          host = "laliga.gamebuild.co"
          http = {
            paths = [
              {
                pathType = "Prefix"
                path     = "/"
                backend = {
                  service = {
                    name = "mobile-api"
                    port = {
                      number = 80
                    }
                  }
                }
              },
              {
                pathType = "Prefix"
                path     = "/api/revenuecat/sync/"
                backend = {
                  service = {
                    name = "mobile-api"
                    port = {
                      number = 80
                    }
                  }
                }
              },
              {
                pathType = "Prefix"
                path     = "/api/users/profile/avatar/"
                backend = {
                  service = {
                    name = "mobile-api"
                    port = {
                      number = 80
                    }
                  }
                }
              },
              {
                pathType = "Prefix"
                path     = "/api"
                backend = {
                  service = {
                    name = "fanclash-api"
                    port = {
                      number = 80
                    }
                  }
                }
              },
              {
                pathType = "Prefix"
                path     = "/api/ws"
                backend = {
                  service = {
                    name = "fanclash-api-ws"
                    port = {
                      number = 80
                    }
                  }
                }
              },
              # {
              #   pathType = "Prefix"
              #   path     = "/api/gorush"
              #   backend = {
              #     service = {
              #       name = "gorush-service"
              #       port = {
              #         number = 8088
              #       }
              #     }
              #   }
              # }
            ]
          }
        }
      ]
      tls = [
        {
          secretName = "letsencrypt-prod"
          hosts      = ["laliga.gamebuild.co"]
        }
      ]
    }
  }
}
