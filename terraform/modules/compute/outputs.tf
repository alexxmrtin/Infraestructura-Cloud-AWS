output "alb_dns_name" {
  description = "Dirección pública del ALB."
  value       = aws_lb.api.dns_name
}

output "alb_zone_id" {
  description = "Zona del ALB (para el registro alias de Route 53)."
  value       = aws_lb.api.zone_id
}

output "alb_arn" {
  description = "ARN del ALB."
  value       = aws_lb.api.arn
}

output "alb_arn_suffix" {
  description = "Final del ARN del ALB: es como lo nombran sus métricas en CloudWatch."
  value       = aws_lb.api.arn_suffix
}

output "target_group_arn_suffix" {
  description = "Final del ARN del target group de la API (para sus métricas)."
  value       = aws_lb_target_group.api.arn_suffix
}

output "alb_security_group_id" {
  description = "Grupo del ALB (solo admite a CloudFront)."
  value       = aws_security_group.alb.id
}

output "ecr_repository_url" {
  description = "Repositorio ECR de la imagen de la API."
  value       = aws_ecr_repository.api.repository_url
}

output "cluster_name" {
  description = "Cluster de ECS."
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "Servicio de ECS de la API."
  value       = aws_ecs_service.api.name
}

output "autoscaling_group_name" {
  description = "Auto Scaling Group de las instancias de ECS."
  value       = aws_autoscaling_group.ecs.name
}

output "api_log_group" {
  description = "Log group de CloudWatch con los logs de la API."
  value       = aws_cloudwatch_log_group.api.name
}

output "backup_vault_name" {
  description = "Almacén de AWS Backup (null si está apagado)."
  value       = try(aws_backup_vault.this[0].name, null)
}
