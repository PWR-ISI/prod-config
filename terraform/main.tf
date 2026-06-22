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

  # SMTP for outbound email notifications
  smtp_host     = var.smtp_host
  smtp_port     = var.smtp_port
  smtp_user     = var.smtp_user
  smtp_password = var.smtp_password
  email_from    = var.email_from
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

module "appointment_lambda" {
  source    = "./modules/appointment-lambda"
  providers = { aws = aws.localstack }

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

module "frontend" {
  source       = "./modules/frontend"
  providers    = { aws = aws.localstack }
  project_name = var.project_name
  region       = var.region
}

# ── Cross-service SNS→SQS subscriptions ───────────────────────────────────────
# Each service module owns its own SNS topic (publish) and SQS inbox (consume).
# Subscriptions are declared here to avoid circular module dependencies.

# appointment-service ECS removed — Lambda publishes directly to notification SQS.
# schedule and notification subscriptions to appointment SNS are no longer needed.

resource "aws_sns_topic_subscription" "notification_subscribes_to_payment" {
  provider  = aws.localstack
  topic_arn = module.payment_service.sns_topic_arn
  protocol  = "sqs"
  endpoint  = module.notification_service.sqs_app_events_arn
}

resource "aws_sns_topic_subscription" "notification_subscribes_to_schedule" {
  provider  = aws.localstack
  topic_arn = module.schedule_service.sns_topic_arn
  protocol  = "sqs"
  endpoint  = module.notification_service.sqs_app_events_arn
}

# Payment events → schedule-service so it can mark appointments as PAID
resource "aws_sns_topic_subscription" "schedule_inbox_subscribes_to_payment" {
  provider  = aws.localstack
  topic_arn = module.payment_service.sns_topic_arn
  protocol  = "sqs"
  endpoint  = module.schedule_service.sqs_queue_arn
}

# appointment_inbox_subscribes_to_schedule removed — appointment ECS no longer exists.
