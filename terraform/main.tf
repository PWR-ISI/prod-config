module "network" {
  source       = "./modules/network"
  providers    = { aws = aws }
  project_name = var.project_name
}

# S3 files bucket + SES + EventBridge Scheduler role
module "storage" {
  source             = "./modules/storage"
  providers          = { aws = aws }
  project_name       = var.project_name
  region             = var.region
  notification_email = var.notification_email
}

module "cognito" {
  source       = "./modules/cognito"
  providers    = { aws = aws }
  project_name = var.project_name
}

module "sqs" {
  source       = "./modules/sqs"
  providers    = { aws = aws }
  project_name = var.project_name
}

# DynamoDB for file metadata + notification history
module "dynamodb" {
  source       = "./modules/dynamodb"
  providers    = { aws = aws }
  project_name = var.project_name
  region       = var.region
}

# SNS for notifications
module "sns_notifications" {
  source             = "./modules/sns-notifications"
  providers          = { aws = aws }
  project_name       = var.project_name
  region             = var.region
  notification_email = var.notification_email
}

# Monitoring & CloudWatch
module "monitoring" {
  source    = "./modules/monitoring"
  providers = { aws = aws }

  project_name                 = var.project_name
  region                       = var.region
  ecs_cluster_name             = "${var.project_name}-schedule-cluster"
  sns_topic_arn                = module.sns_notifications.appointment_topic_arn
  schedule_service_target_group = "${var.project_name}-schedule-tg"
}

# module "auth_service" {
#   source    = "./modules/auth-identity-service"
#   providers = { aws = aws }
#
#   project_name          = var.project_name
#   region                = var.region
#   vpc_id                = module.network.vpc_id
#   public_subnets        = module.network.public_subnets
#   private_subnets       = module.network.private_subnets
#   db_subnets            = module.network.db_subnets
#   ecs_security_group_id = module.network.ecs_sg_id
#   db_security_group_id  = module.network.db_sg_id
#   db_username           = var.db_username
#   db_password           = var.db_password
#   cognito_user_pool_id  = module.cognito.user_pool_id
#   cognito_app_client_id = module.cognito.app_client_id
# }

module "notification_service" {
  source    = "./modules/notification-service"
  providers = { aws = aws }

  project_name            = var.project_name
  region                  = var.region
  vpc_id                  = module.network.vpc_id
  public_subnets          = module.network.public_subnets
  private_subnets         = module.network.private_subnets
  ecs_security_group_id   = module.network.ecs_sg_id
  cognito_user_pool_id    = module.cognito.user_pool_id
  cognito_user_pool_arn   = module.cognito.user_pool_arn
  scheduler_exec_role_arn = module.storage.scheduler_exec_role_arn
  notification_email      = var.notification_email
  sender_email            = var.notification_email
  files_bucket_name       = module.storage.files_bucket_name
}

# Subscribe notification-service SQS to schedule SNS topic (appointment events)
# SNS topic (schedule-service) → SQS queue (notification-service) → consumer → Cognito lookup → SES per-user email
resource "aws_sns_topic_subscription" "notif_subscribes_schedule" {
  topic_arn = module.schedule_service.sns_topic_arn
  protocol  = "sqs"
  endpoint  = module.notification_service.sqs_notification_jobs_arn
}

# facility_service disabled - not needed for MVP
# module "facility_service" {
#   source    = "./modules/facility-staff-service"
#   providers = { aws = aws }
#
#   project_name          = var.project_name
#   region                = var.region
#   vpc_id                = module.network.vpc_id
#   public_subnets        = module.network.public_subnets
#   private_subnets       = module.network.private_subnets
#   db_subnets            = module.network.db_subnets
#   ecs_security_group_id = module.network.ecs_sg_id
#   db_security_group_id  = module.network.db_sg_id
#   db_username           = var.db_username
#   db_password           = var.db_password
#   cognito_user_pool_id  = module.cognito.user_pool_id
# }

# medical_service disabled - not needed for MVP
# module "medical_service" {
#   source    = "./modules/medical-record-service"
#   providers = { aws = aws }
#
#   project_name          = var.project_name
#   region                = var.region
#   vpc_id                = module.network.vpc_id
#   public_subnets        = module.network.public_subnets
#   private_subnets       = module.network.private_subnets
#   db_subnets            = module.network.db_subnets
#   ecs_security_group_id = module.network.ecs_sg_id
#   db_security_group_id  = module.network.db_sg_id
#   db_username           = var.db_username
#   db_password           = var.db_password
#   cognito_user_pool_id  = module.cognito.user_pool_id
# }

# audit_service disabled - not needed for MVP
# module "audit_service" {
#   source    = "./modules/audit-logging-service"
#   providers = { aws = aws }
#
#   project_name          = var.project_name
#   region                = var.region
#   vpc_id                = module.network.vpc_id
#   public_subnets        = module.network.public_subnets
#   private_subnets       = module.network.private_subnets
#   db_subnets            = module.network.db_subnets
#   ecs_security_group_id = module.network.ecs_sg_id
#   db_security_group_id  = module.network.db_sg_id
#   db_username           = var.db_username
#   db_password           = var.db_password
#   cognito_user_pool_id  = module.cognito.user_pool_id
# }

# appointment_service disabled - not needed for MVP (use schedule_service instead)
# module "appointment_service" {
#   source    = "./modules/appointment-service"
#   providers = { aws = aws }
#
#   project_name          = var.project_name
#   region                = var.region
#   vpc_id                = module.network.vpc_id
#   public_subnets        = module.network.public_subnets
#   private_subnets       = module.network.private_subnets
#   db_subnets            = module.network.db_subnets
#   ecs_security_group_id = module.network.ecs_sg_id
#   db_security_group_id  = module.network.db_sg_id
#   db_username           = var.db_username
#   db_password           = var.db_password
#   sqs_app_events_url    = "" # module.notification_service.sqs_app_events_url (disabled)
#   cognito_user_pool_id  = module.cognito.user_pool_id
# }

module "schedule_service" {
  source    = "./modules/schedule-service"
  providers = { aws = aws }

  project_name                  = var.project_name
  region                        = var.region
  vpc_id                        = module.network.vpc_id
  public_subnets               = module.network.public_subnets
  private_subnets              = module.network.private_subnets
  db_subnets                   = module.network.db_subnets
  ecs_security_group_id        = module.network.ecs_sg_id
  central_alb_target_group_arn = module.central_alb.schedule_target_group_arn
  db_security_group_id         = module.network.db_sg_id
  db_username                  = var.db_username
  db_password                  = var.db_password
  files_bucket_name            = module.storage.files_bucket_name
  files_bucket_arn             = module.storage.files_bucket_arn
}

module "file_upload_service" {
  source    = "./modules/file-upload-service"
  providers = { aws = aws }

  project_name                  = var.project_name
  region                        = var.region
  vpc_id                        = module.network.vpc_id
  public_subnets               = module.network.public_subnets
  private_subnets              = module.network.private_subnets
  db_subnets                   = module.network.db_subnets
  ecs_security_group_id        = module.network.ecs_sg_id
  central_alb_target_group_arn = module.central_alb.file_upload_target_group_arn
  db_security_group_id         = module.network.db_sg_id
  db_username                  = var.db_username
  db_password                  = var.db_password
  files_bucket_name            = module.storage.files_bucket_name
  files_bucket_arn             = module.storage.files_bucket_arn
}

# payment_service disabled - not needed for MVP
# module "payment_service" {
#   source    = "./modules/payment-service"
#   providers = { aws = aws }
#
#   project_name             = var.project_name
#   region                   = var.region
#   vpc_id                   = module.network.vpc_id
#   public_subnets           = module.network.public_subnets
#   private_subnets          = module.network.private_subnets
#   db_subnets               = module.network.db_subnets
#   ecs_security_group_id    = module.network.ecs_sg_id
#   db_security_group_id     = module.network.db_sg_id
#   db_username              = var.db_username
#   db_password              = var.db_password
#   payu_merchant_id         = var.payu_merchant_id
#   payu_api_key             = var.payu_api_key
#   payu_oauth_client_id     = var.payu_oauth_client_id
#   payu_oauth_client_secret = var.payu_oauth_client_secret
# }

# Commented out - using direct ALB with path-based routing instead
# module "api_gateway" {
#   source    = "./modules/api-gateway"
#   ...
# }

module "central_alb" {
  source       = "./modules/central-alb"
  project_name = var.project_name
  vpc_id       = module.network.vpc_id
  public_subnets = module.network.public_subnets
}

module "frontend" {
  source       = "./modules/frontend"
  providers    = { aws = aws }
  project_name = var.project_name
  region       = var.region
}

# ── Cross-service SNS→SQS subscriptions ───────────────────────────────────────
# Each service module owns its own SNS topic (publish) and SQS inbox (consume).
# Subscriptions are declared here to avoid circular module dependencies.

# resource "aws_sns_topic_subscription" "schedule_inbox_subscribes_to_appointment" {
#   provider  = aws.localstack
#   topic_arn = module.appointment_service.sns_topic_arn
#   protocol  = "sqs"
#   endpoint  = module.schedule_service.sqs_queue_arn
# }
#
# resource "aws_sns_topic_subscription" "appointment_inbox_subscribes_to_schedule" {
#   provider  = aws.localstack
#   topic_arn = module.schedule_service.sns_topic_arn
#   protocol  = "sqs"
#   endpoint  = module.appointment_service.sqs_queue_arn
# }

