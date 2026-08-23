# Cria VPC — rede isolada do cluster (módulo comunitário reutilizável)
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "mecanicadm-${var.environment}"
  cidr = var.vpc_cidr

  # Três AZs garantem alta disponibilidade do plano de dados.
  azs             = ["${var.region}a", "${var.region}b", "${var.region}c"]
  private_subnets = [for i, az in ["${var.region}a", "${var.region}b", "${var.region}c"] : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i, az in ["${var.region}a", "${var.region}b", "${var.region}c"] : cidrsubnet(var.vpc_cidr, 4, i + 3)]

  # NAT Gateway garante que o cluster acesse a internet (ex.: pull de imagens).
  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Environment = var.environment }
}

# Cluster EKS, roles IAM e node group: definidos em eks.tf (recursos nativos)

# Namespace de negócio — onde a API principal será instalada via Helm (o repo mecanicadm-api-v3 aponta para este namespace no helm upgrade)
resource "kubernetes_namespace_v1" "mecanicadm" {
  metadata {
    name = "mecanicadm"
    labels = {
      environment = var.environment
    }
  }

  depends_on = [aws_eks_node_group.workers]
}

# Cria API Gateway (Kong)
resource "helm_release" "kong" {
  name             = "kong"
  repository       = "https://charts.konghq.com"
  chart            = "kong"
  version          = var.kong_chart_version
  namespace        = "kong"
  create_namespace = true

  set {
    name  = "proxy.type"
    value = "LoadBalancer"
  }

  set {
    name  = "ingressController.enabled"
    value = "true"
  }

  depends_on = [aws_eks_node_group.workers]
}

# Observabilidade — Prometheus (métricas), Grafana (dashboards) e Alertmanager (alertas). O Prometheus coleta métricas do app via /actuator/prometheus (Spring Boot) e do cluster (node-exporter).
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.kube_prometheus_stack_chart_version
  namespace        = "monitoring"
  create_namespace = true

  set {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }

  set {
    name  = "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues"
    value = "false"
  }

  # Retenção curta de métricas: reduz consumo de RAM/disco no node
  # sem perder o histórico recente usado nos dashboards.
  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "2d"
  }

  depends_on = [aws_eks_node_group.workers]
}

# ---------------------------------------------------------------------------
# External Secrets Operator — sincroniza automaticamente secrets do
# AWS SSM Parameter Store para K8s Secrets. Quando o db-v3 rotaciona a
# senha do RDS e publica no SSM, o ESO detecta a mudança e atualiza o
# K8s Secret sem necessidade de redeploy manual.
# ---------------------------------------------------------------------------
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_chart_version
  namespace        = "external-secrets"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [aws_eks_node_group.workers]
}

# Anota o ServiceAccount do ESO com o IAM Role (IRSA) para acesso ao SSM
resource "null_resource" "eso_irsa_annotation" {
  depends_on = [helm_release.external_secrets]

  provisioner "local-exec" {
    command = <<-EOT
      kubectl annotate serviceaccount external-secrets \
        --namespace external-secrets \
        eks.amazonaws.com/role-arn=${aws_iam_role.eso.arn} \
        --overwrite
    EOT
  }
}

# IAM Role para o ServiceAccount do ESO (IRSA) — concede acesso leitura ao SSM
data "aws_caller_identity" "current" {}

resource "aws_iam_role" "eso" {
  name = "mecanicadm-${var.environment}-eso"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(local.oidc_issuer_url, "https://", "")}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(local.oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:external-secrets:external-secrets"
          "${replace(local.oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "eso_ssm" {
  name = "ssm-read"
  role = aws_iam_role.eso.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter", "ssm:GetParameters"]
      Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/mecanicadm/${var.environment}/*"
    }]
  })
}

resource "aws_security_group" "lambda" {
  name   = "mecanicadm-${var.environment}-lambda"
  vpc_id = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # NAT Gateways dão acesso à internet (SSM etc.)
  }

  tags = { Environment = var.environment }
}

resource "aws_ssm_parameter" "vpc_id" {
  name  = "/mecanicadm/${var.environment}/vpc_id"
  type  = "String"
  value = module.vpc.vpc_id
}

resource "aws_ssm_parameter" "lambda_sg_id" {
  name  = "/mecanicadm/${var.environment}/lambda_sg_id"
  type  = "String"
  value = aws_security_group.lambda.id
}

resource "aws_ssm_parameter" "lambda_subnet_a" {
  name  = "/mecanicadm/${var.environment}/lambda_subnet_a"
  type  = "String"
  value = module.vpc.private_subnets[0]
}

resource "aws_ssm_parameter" "lambda_subnet_b" {
  name  = "/mecanicadm/${var.environment}/lambda_subnet_b"
  type  = "String"
  value = module.vpc.private_subnets[1]
}

resource "aws_ssm_parameter" "eks_node_sg_id" {
  name  = "/mecanicadm/${var.environment}/eks_node_sg_id"
  type  = "String"
  value = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

# ---------------------------------------------------------------------------
# 8) Segredo do JWT — gerado AQUI (repo 2) e publicado no SSM.
# ---------------------------------------------------------------------------
# O JWT não tem relação com o banco: é a assinatura compartilhada entre a
# Lambda (repo 1, que emite) e a API (repo 4, que valida). Por isso a geração
# fica neste repositório, dono do runtime da aplicação, junto com os demais
# parâmetros que a esteira de deploy consome. O valor nunca passa por código.
# ---------------------------------------------------------------------------
resource "random_password" "jwt_secret" {
  length  = 64
  special = false # base64-safe, evita problemas de escape
}

resource "aws_ssm_parameter" "jwt_secret" {
  name  = "/mecanicadm/${var.environment}/jwt_secret"
  type  = "SecureString"
  value = random_password.jwt_secret.result
}

resource "aws_ssm_parameter" "jwt_expires_minutes" {
  name  = "/mecanicadm/${var.environment}/jwt_expires_minutes"
  type  = "String"
  value = tostring(var.jwt_expires_minutes)
}
