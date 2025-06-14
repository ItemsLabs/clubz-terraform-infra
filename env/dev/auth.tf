# module "doks_auth" {
#   source = "../terraform/k8s-doks-auth"

#   // Pass relevant parameters required by your DOKS module
#   // For example, cluster name or any other necessary information
#   cluster_name = digitalocean_kubernetes_cluster.fanclash_cluster.name

#   // ...any other required variables
# }

# resource "kubernetes_role" "cluster_admins" {
#   metadata {
#     name      = "${var.namespace}cluster-admins"
#     namespace = var.namespace  # You can choose the appropriate namespace
#   }

#   rule {
#     api_groups = ["*"]
#     resources  = ["*"] # "pods", "services", "configmaps", "secrets", "deployments", "pods/exec"
#     verbs      = ["*"] # "create", "get", "list", "update", "delete", "patch", "watch"
#   } 
# }

# resource "kubernetes_role_binding" "cluster_admins_binding" {
#   metadata {
#     name      = "${var.namespace}-cluster-admins-binding"
#     namespace = var.namespace  # You can choose the appropriate namespace
#   }

#   role_ref {
#     api_group = "rbac.authorization.k8s.io"
#     kind      = "ClusterRole"
#     name      = kubernetes_role.cluster_admins.metadata[0].name
#   }

#   subject {
#     kind      = "User"
#     name      = "dmitry.kireev"  # Replace with the actual username
#   }
#   subject {
#     kind      = "ServiceAccount"
#     name      = "default"
#     namespace = "kube-system"
#   }
#   subject {
#     kind      = "Group"
#     name      = "system:masters"
#     api_group = "rbac.authorization.k8s.io"
#   }

#   # Repeat the 'subject' block for each user you want to grant access
#   # to the 'cluster-admins' role.
# }
