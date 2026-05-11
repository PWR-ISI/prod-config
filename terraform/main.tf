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

module "schedule_service" {
  source = "./modules/schedule-service"
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

# Cross-service subscriptions are declared here (not inside the modules) to
# break the cycle that would arise if each module referenced the other's
# topic. Each module owns its topic and inbox queue; the subscriptions glue
# them together.
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

module "notification_service" {
  source = "./modules/notification-service"
  providers = {
    aws = aws.localstack
  }

  project_name = var.project_name
  region       = var.region
}
