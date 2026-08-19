data "kubernetes_service" "kong_proxy" {
  metadata {
    name      = "kong-kong-proxy"
    namespace = "kong"
  }

  depends_on = [helm_release.kong]
}

output "cluster_name" {
  description = "Nome do cluster EKS (usado pelo aws eks update-kubeconfig)."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint do API Server do cluster (uso didático/auditoria)."
  value       = module.eks.cluster_endpoint
}

output "kong_load_balancer_hostname" {
  description = "Hostname do LoadBalancer do API Gateway Kong (DNS externo)."
  value = try(
    data.kubernetes_service.kong_proxy.status[0].load_balancer[0].ingress[0].hostname,
    data.kubernetes_service.kong_proxy.status[0].load_balancer[0].ingress[0].ip,
    ""
  )
}

output "vpc_id" {
  description = "ID da VPC criada para o cluster."
  value       = module.vpc.vpc_id
}

output "lambda_sg_id" {
  description = "ID do Security Group da Lambda (publicado também no SSM)."
  value       = aws_security_group.lambda.id
}
