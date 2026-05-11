module "network" {
  source       = "./modules/network"
  providers    = { aws = aws.localstack }
  project_name = var.project_name
}

module "cognito" {
  source       = "./modules/cognito"
  providers    = { aws = aws.localstack }
  project_name = var.project_name
}

module "notification_service" {
  source       = "./modules/notification-service"
  providers    = { aws = aws.localstack }
  project_name = var.project_name
  region       = var.region
}

module "appointment_service" {
  source    = "./modules/appointment-service"
  providers = { aws = aws.localstack }

  project_name          = var.project_name
  region                = var.region
  vpc_id                = module.network.vpc_id
  public_subnets        = module.network.public_subnets
  private_subnets       = module.network.private_subnets
  db_subnets            = module.network.db_subnets
  ecs_security_group_id = module.network.ecs_sg_id
  db_security_group_id  = module.network.db_sg_id
  db_username           = var.db_username
  db_password           = var.db_password
  sqs_app_events_url    = module.notification_service.sqs_app_events_url
  cognito_user_pool_id  = module.cognito.user_pool_id
}

module "api_gateway" {
  source       = "./modules/api-gateway"
  providers    = { aws = aws.localstack }
  project_name = var.project_name
}

module "frontend" {
  source       = "./modules/frontend"
  providers    = { aws = aws.localstack }
  project_name = var.project_name
  region       = var.region
}
