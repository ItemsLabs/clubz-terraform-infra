# resource "kubernetes_deployment" "gorush" {
#   metadata {
#     name      = "gorush"
#     namespace = "fanclash-dev"
#   }

#   spec {
#     replicas = var.gorush_replicas

#     selector {
#       match_labels = {
#         app = "gorush"
#       }
#     }

#     template {
#       metadata {
#         labels = {
#           app = "gorush"
#         }
#       }

#       spec {
#         container {
#           image = var.gorush_image
#           name  = "gorush"
#           port {
#             container_port = 8088
#           }
#           image_pull_policy = "Always"
#           env {
#             name  = "FIREBASE_API_KEY"
#             value_from {
#               secret_key_ref {
#                 name = "gorush-creds"
#                 key  = "FIREBASE_API_KEY"
#               }
#             }
#           }

#           env {
#             name  = "IOS_CERTIFICATE"
#             value_from {
#               secret_key_ref {
#                 name = "gorush-creds"
#                 key  = "IOS_CERTIFICATE"
#               }
#             }
#           }

#           env {
#             name  = "IOS_CERTIFICATE_KEY"
#             value_from {
#               secret_key_ref {
#                 name = "gorush-creds"
#                 key  = "IOS_CERTIFICATE_KEY"
#               }
#             }
#           }
#         }
#       }
#     }
#   }
# }


# resource "kubernetes_service" "gorush" {
#   metadata {
#     name      = "gorush-service"
#     namespace = "fanclash-dev"
#     labels = {
#       app = "gorush"
#     }
#   }

#   spec {
#     selector = {
#       app = "gorush"
#     }

#     port {
#       port        = 8088
#       target_port = 8088
#     }
#   }
# }
