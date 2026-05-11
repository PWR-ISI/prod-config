output "alb_dns" {
  value = aws_lb.alb.dns_name
}

output "db_endpoint" {
  value = aws_db_instance.core.address
}

output "ecr_repository_url" {
  value = aws_ecr_repository.core.repository_url
}

output "ecs_cluster" {
  value = aws_ecs_cluster.cluster.name
}

output "ecs_service" {
  value = aws_ecs_service.service.name
}
