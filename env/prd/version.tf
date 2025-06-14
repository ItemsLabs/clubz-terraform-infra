terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.12.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.25.2"
    }
  }
  required_version = ">= 0.15"
  backend "s3" {
    bucket         = "fanclash-prd-tfstate"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "fanclash-prd-tfstate"
    encrypt        = true
    # profile = "infra-dev"
  }
}


# Configure the DigitalOcean Provider
provider "digitalocean" {
  token             = var.do_token
  # spaces_access_id  = var.do_spaces_access_id
  # spaces_secret_key = var.do_spaces_secret_key
}

provider "aws" {
  region = var.aws_region
  # profile = "infra-dev"
  default_tags {
    tags = {
      Environment = var.env
      Owner       = var.company
      Project     = var.project
      Terraform   = "true"
    }
  }
}

provider "helm" {
  kubernetes {
    host = data.digitalocean_kubernetes_cluster.fanclash_cluster.endpoint
    cluster_ca_certificate = base64decode(
      data.digitalocean_kubernetes_cluster.fanclash_cluster.kube_config[0].cluster_ca_certificate
    )
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "doctl"
      args = ["kubernetes", "cluster", "kubeconfig", "exec-credential",
      "--version=v1beta1", data.digitalocean_kubernetes_cluster.fanclash_cluster.id]
    }
  }
}

provider "kubectl" {
  host = data.digitalocean_kubernetes_cluster.fanclash_cluster.endpoint
  cluster_ca_certificate = base64decode(
    data.digitalocean_kubernetes_cluster.fanclash_cluster.kube_config[0].cluster_ca_certificate
  )
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "doctl"
    args = ["kubernetes", "cluster", "kubeconfig", "exec-credential",
    "--version=v1beta1", data.digitalocean_kubernetes_cluster.fanclash_cluster.id]
  }
}

provider "kubernetes" {
  host  = data.digitalocean_kubernetes_cluster.fanclash_cluster.endpoint
  token = data.digitalocean_kubernetes_cluster.fanclash_cluster.kube_config[0].token
  cluster_ca_certificate = base64decode(
    data.digitalocean_kubernetes_cluster.fanclash_cluster.kube_config[0].cluster_ca_certificate
  )
}

data "digitalocean_kubernetes_cluster" "fanclash_cluster" {
  name = var.namespace
}