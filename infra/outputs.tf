# Load Balancer DNS name
output "load_balancer_dns" {
  description = "DNS name of the load balancer"
  value       = aws_lb.backend.dns_name
}

# Load Balancer URL
output "load_balancer_url" {
  description = "URL of the load balancer"
  value       = "http://${aws_lb.backend.dns_name}"
}

# VPC ID
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

# Private subnet IDs
output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

# Public subnet IDs
output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

# Auto Scaling Group name
output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.backend.name
}

# RDS endpoint
# output "rds_endpoint" {
#   description = "RDS instance endpoint"
#   value       = aws_db_instance.main.endpoint
#   sensitive   = true
# }

# Security Group IDs
output "ec2_security_group_id" {
  description = "Security Group ID for EC2 instances"
  value       = aws_security_group.ec2.id
}

output "alb_security_group_id" {
  description = "Security Group ID for ALB"
  value       = aws_security_group.alb.id
}

output "rds_security_group_id" {
  description = "Security Group ID for RDS"
  value       = aws_security_group.rds.id
}

# ===== EKS Outputs =====

output "eks_cluster_name" {
  description = "Назва EKS кластера"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint EKS кластера"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_certificate_authority" {
  description = "Certificate Authority EKS кластера (base64)"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "eks_oidc_provider_arn" {
  description = "ARN OIDC провайдера для EKS"
  value       = module.eks.oidc_provider_arn
}

output "ecr_repository_url" {
  description = "URL ECR репозиторію"
  value       = aws_ecr_repository.main.repository_url
}

output "eks_kubeconfig_command" {
  description = "Команда для оновлення kubeconfig"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
