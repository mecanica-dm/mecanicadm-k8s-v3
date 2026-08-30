terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.region
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

data "helm_repository" "kong" {
  name = "kong"
  url  = "https://charts.konghq.com"
}

data "helm_repository" "metrics_server" {
  name = "metrics-server"
  url  = "https://kubernetes-sigs.github.io/metrics-server/"
}

data "helm_repository" "newrelic" {
  name = "newrelic"
  url  = "https://helm-charts.newrelic.com"
}

data "helm_repository" "external_secrets" {
  name = "external-secrets"
  url  = "https://charts.external-secrets.io"
}

data "helm_repository" "external_dns" {
  name = "external-dns"
  url  = "https://kubernetes-sigs.github.io/external-dns/"
}
