module "appointment_service" {
  source = "./modules/appointment-service"
  providers = {
    aws = aws.localstack
  }

  project_name          = var.project_name
  region                = var.region
  vpc_id                = var.vpc_id
  public_subnets        = var.public_subnets
  private_subnets       = var.private_subnets
  db_subnets            = var.db_subnets
  ecs_security_group_id = var.ecs_security_group_id
  db_security_group_id  = var.db_security_group_id
  db_username           = var.db_username
  db_password           = var.db_password
}

module "notification_service" {
  source = "./modules/notification-service"
  providers = {
    aws = aws.localstack
  }

  project_name = var.project_name
  region       = var.region
}