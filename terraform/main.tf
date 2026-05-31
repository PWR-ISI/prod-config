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

module "sqs" {
  source       = "./modules/sqs"
  providers    = { aws = aws.localstack }
  project_name = var.project_name
}

module "auth_service" {
  source    = "./modules/auth-identity-service"
  providers = { aws = aws.localstack }

  project_name            = var.project_name
  region                  = var.region
  vpc_id                  = module.network.vpc_id
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
  source    = "./modules/notification-service"
  providers = { aws = aws.localstack }

  project_name          = var.project_name
  region                = var.region
  vpc_id                = module.network.vpc_id
  public_subnets        = module.network.public_subnets
  private_subnets       = module.network.private_subnets
  ecs_security_group_id = module.network.ecs_sg_id

  # Google Calendar OAuth2 (Priority 2). Defaults are empty — set via
  # TF_VAR_google_oauth_* in the deploy shell to activate.
  google_oauth_client_id      = var.google_oauth_client_id
  google_oauth_client_secret  = var.google_oauth_client_secret
  google_oauth_redirect_uri   = var.google_oauth_redirect_uri
  google_token_encryption_key = var.google_token_encryption_key
}

module "facility_service" {
  source    = "./modules/facility-staff-service"
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
  cognito_user_pool_id  = module.cognito.user_pool_id
}

module "medical_service" {
  source    = "./modules/medical-record-service"
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
  cognito_user_pool_id  = module.cognito.user_pool_id
}

module "audit_service" {
  source    = "./modules/audit-logging-service"
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
  cognito_user_pool_id  = module.cognito.user_pool_id
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

module "schedule_service" {
  source    = "./modules/schedule-service"
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
  db_username              = var.db_username
  db_password              = var.db_password
  payu_merchant_id         = var.payu_merchant_id
  payu_api_key             = var.payu_api_key
  payu_oauth_client_id     = var.payu_oauth_client_id
  payu_oauth_client_secret = var.payu_oauth_client_secret
}

module "api_gateway" {
  source       = "./modules/api-gateway"
  providers    = { aws = aws.localstack }

  project_name          = var.project_name
  region                = var.region
  cognito_user_pool_id  = module.cognito.user_pool_id
  cognito_app_client_id = module.cognito.app_client_id
  use_direct_service_routing = var.use_direct_service_routing

  # For both LocalStack and AWS: Use ALB DNS names (API Gateway → ALB → ECS targets)
  # ALB listens on port 80 and forwards to port 8000 on ECS tasks
  appointment_service_endpoint    = module.appointment_service.alb_dns
  payment_service_endpoint        = module.payment_service.alb_dns
  auth_service_endpoint           = module.auth_service.alb_dns
  schedule_service_endpoint       = module.schedule_service.alb_dns
  notification_service_endpoint   = module.notification_service.alb_dns
  facility_staff_service_endpoint = module.facility_service.alb_dns
  medical_record_service_endpoint = module.medical_service.alb_dns
  audit_service_endpoint          = module.audit_service.alb_dns
}

module "frontend" {
  source       = "./modules/frontend"
  providers    = { aws = aws.localstack }
  project_name = var.project_name
  region       = var.region
}

# ── Cross-service SNS→SQS subscriptions ───────────────────────────────────────
# Each service module owns its own SNS topic (publish) and SQS inbox (consume).
# Subscriptions are declared here to avoid circular module dependencies.

resource "aws_sns_topic_subscription" "schedule_inbox_subscribes_to_appointment" {
  provider  = aws.localstack
  topic_arn = module.appointment_service.sns_topic_arn
  protocol  = "sqs"
  endpoint  = module.schedule_service.sqs_queue_arn
}

resource "aws_sns_topic_subscription" "appointment_inbox_subscribes_to_schedule" {
  provider  = aws.localstack
  topic_arn = module.schedule_service.sns_topic_arn
  protocol  = "sqs"
  endpoint  = module.appointment_service.sqs_queue_arn
}
