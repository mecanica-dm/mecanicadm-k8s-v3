variable "region" {
  description = "Região AWS onde o cluster será criado."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Ambiente (apenas produção por orientação do projeto)."
  type        = string
  default     = "prod"
  validation {
    condition     = var.environment == "prod"
    error_message = "Apenas o ambiente de produção (prod) é suportado."
  }
}

variable "cluster_name" {
  description = "Nome do cluster EKS (ex.: mecanicadm-prod)."
  type        = string
  default     = "mecanicadm-prod"
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC do cluster (ex.: 10.0.0.0/16)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "cluster_version" {
  description = "Versão do Kubernetes gerenciada pelo EKS."
  type        = string
  default     = "1.29"
}

variable "node_instance_types" {
  description = "Tipos de instância dos worker nodes (adequados à carga de produção)."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Número desejado de worker nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Mínimo de worker nodes (escala automática)."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Máximo de worker nodes (escala automática)."
  type        = number
  default     = 2
}

variable "kong_chart_version" {
  description = "Versão do chart Helm do Kong (API Gateway)."
  type        = string
  default     = "2.45.0"
}

variable "kube_prometheus_stack_chart_version" {
  description = "Versão do chart kube-prometheus-stack (Prometheus + Grafana)."
  type        = string
  default     = "62.0.0"
}

variable "grafana_admin_password" {
  description = "Senha do admin do Grafana (secret da pipeline via TF_VAR)."
  type        = string
  sensitive   = true
}

variable "jwt_expires_minutes" {
  description = "Validade dos tokens JWT emitidos pela Lambda (em minutos)."
  type        = number
  default     = 60
}

variable "external_secrets_chart_version" {
  description = "Versão do chart External Secrets Operator."
  type        = string
  default     = "0.12.1"
}

variable "route53_zone_name" {
  description = "Domínio da hosted zone Route 53 criada pela pasta dns/ (usado pelo ExternalDNS)."
  type        = string
  default     = "mecanicadm.com.br"
}

variable "external_dns_enabled" {
  description = "Habilita o ExternalDNS (requer a zona já criada pelo workflow DNS - Hosted Zone)."
  type        = bool
  default     = true
}

variable "external_dns_chart_version" {
  description = "Versão do chart Helm do ExternalDNS."
  type        = string
  default     = "1.15.0"
}
