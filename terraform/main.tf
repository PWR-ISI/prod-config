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

module "payment_service" {
  source    = "./modules/payment-service"
  providers = { aws = aws.localstack }

  project_name             = var.project_name
  region                   = var.region
  vpc_id                   = module.network.vpc_id
  public_subnets           = module.network.public_subnets
  private_subnets          = module.network.private_subnets
  db_subnets               = module.network.db_subnets
  ecs_security_group_id    = module.network.ecs_sg_id
  db_security_group_id     = module.network.db_sg_id
  db_host                  = "postgres-payment"
  db_username              = "payment_user"
  db_password              = "payment_pass"
  payu_merchant_id         = var.payu_merchant_id
  payu_api_key             = var.payu_api_key
  payu_oauth_client_id     = var.payu_oauth_client_id
  payu_oauth_client_secret = var.payu_oauth_client_secret
}

module "api_gateway" {
  source       = "./modules/api-gateway"
  providers    = { aws = aws.localstack }
  project_name = var.project_name
  payment_service_url = module.payment_service.alb_url
}

module "frontend" {
  source       = "./modules/frontend"
  providers    = { aws = aws.localstack }
  project_name = var.project_name
  region       = var.region
}
