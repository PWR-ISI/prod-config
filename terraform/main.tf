module "network" {
  source       = "./modules/network"
  project_name = var.project_name
}

module "cognito" {
  source       = "./modules/cognito"
  project_name = var.project_name
}

module "sqs" {
  source       = "./modules/sqs"
  project_name = var.project_name
}

module "auth_service" {
  source = "./modules/auth-identity-service"

  project_name           = var.project_name
  region                 = var.region
  vpc_id                 = module.network.vpc_id
  public_subnets         = module.network.public_subnets
  private_subnets        = module.network.private_subnets
  db_subnets             = module.network.db_subnets
  ecs_security_group_id  = module.network.ecs_sg_id
  db_security_group_id   = module.network.db_sg_id
  db_username            = var.db_username
  db_password            = var.db_password
  cognito_user_pool_id   = module.cognito.user_pool_id
  cognito_app_client_id  = module.cognito.app_client_id
}

module "notification_service" {
  source = "./modules/notification-service"

  project_name          = var.project_name
  region                = var.region
  vpc_id                = module.network.vpc_id
  public_subnets        = module.network.public_subnets
  private_subnets       = module.network.private_subnets
  ecs_security_group_id = module.network.ecs_sg_id
  auth_service_url      = "http://${module.auth_service.alb_dns}/api/v2"

  google_oauth_client_id      = var.google_oauth_client_id
  google_oauth_client_secret  = var.google_oauth_client_secret
  google_oauth_redirect_uri   = var.google_oauth_redirect_uri
  google_token_encryption_key = var.google_token_encryption_key

  smtp_host     = var.smtp_host
  smtp_port     = var.smtp_port
  smtp_user     = var.smtp_user
  smtp_password = var.smtp_password
  email_from    = var.email_from
}

module "facility_service" {
  source = "./modules/facility-staff-service"

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
  cognito_user_pool_id  = module.cognito.user_pool_id
}

module "medical_service" {
  source = "./modules/medical-record-service"

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
  cognito_user_pool_id  = module.cognito.user_pool_id
}

module "audit_service" {
  source = "./modules/audit-logging-service"

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
  cognito_user_pool_id  = module.cognito.user_pool_id
}

module "appointment_lambda" {
  source = "./modules/appointment-lambda"

  project_name          = var.project_name
  region                = var.region
  vpc_id                = module.network.vpc_id
  private_subnets       = module.network.private_subnets
  db_subnets            = module.network.db_subnets
  ecs_security_group_id = module.network.ecs_sg_id
  db_security_group_id  = module.network.db_sg_id
  db_username           = var.db_username
  db_password           = var.db_password
  notification_sqs_url  = module.notification_service.sqs_app_events_url
  cognito_user_pool_id  = module.cognito.user_pool_id
}

module "schedule_service" {
  source = "./modules/schedule-service"

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
}

module "payment_service" {
  source = "./modules/payment-service"

  project_name             = var.project_name
  region                   = var.region
  vpc_id                   = module.network.vpc_id
  public_subnets           = module.network.public_subnets
  private_subnets          = module.network.private_subnets
  db_subnets               = module.network.db_subnets
  ecs_security_group_id    = module.network.ecs_sg_id
  db_security_group_id     = module.network.db_sg_id
  db_username              = var.db_username
  db_password              = var.db_password
  payu_merchant_id         = var.payu_merchant_id
  payu_api_key             = var.payu_api_key
  payu_oauth_client_id     = var.payu_oauth_client_id
  payu_oauth_client_secret = var.payu_oauth_client_secret
  frontend_url             = module.frontend.website_endpoint
}

module "frontend" {
  source       = "./modules/frontend"
  project_name = var.project_name
  region       = var.region
}

# ── Cross-service SNS→SQS subscriptions ───────────────────────────────────────
# Each service module owns its own SNS topic (publish) and SQS inbox (consume).
# Subscriptions are declared here to avoid circular module dependencies.

# appointment-service ECS removed — Lambda publishes directly to notification SQS.
resource "aws_sns_topic_subscription" "notification_subscribes_to_payment" {
  topic_arn = module.payment_service.sns_topic_arn
  protocol  = "sqs"
  endpoint  = module.notification_service.sqs_app_events_arn
}

resource "aws_sns_topic_subscription" "notification_subscribes_to_schedule" {
  topic_arn = module.schedule_service.sns_topic_arn
  protocol  = "sqs"
  endpoint  = module.notification_service.sqs_app_events_arn
}

# Payment events → schedule-service so it can mark appointments as PAID
resource "aws_sns_topic_subscription" "schedule_inbox_subscribes_to_payment" {
  topic_arn = module.payment_service.sns_topic_arn
  protocol  = "sqs"
  endpoint  = module.schedule_service.sqs_queue_arn
}
