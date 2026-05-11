module "cognito" {
  source = "./modules/cognito"
  providers = {
    aws = aws.localstack
  }

  project_name = var.project_name
}

module "sqs" {
  source = "./modules/sqs"
  providers = {
    aws = aws.localstack
  }

  project_name = var.project_name
}

module "api_gateway" {
  source = "./modules/api-gateway"
  providers = {
    aws = aws.localstack
  }

  project_name          = var.project_name
  region                = var.region
  cognito_user_pool_id  = module.cognito.user_pool_id
  cognito_app_client_id = module.cognito.app_client_id

  # In production these are ALB DNS names; set via tfvars or CI pipeline
  auth_service_endpoint           = var.auth_service_endpoint
  appointment_service_endpoint    = var.appointment_service_endpoint
  schedule_service_endpoint       = var.schedule_service_endpoint
  payment_service_endpoint        = var.payment_service_endpoint
  notification_service_endpoint   = var.notification_service_endpoint
  facility_staff_service_endpoint = var.facility_staff_service_endpoint
  medical_record_service_endpoint = var.medical_record_service_endpoint
  audit_service_endpoint          = var.audit_service_endpoint
}

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

module "frontend" {
  source = "./modules/frontend"
  providers = {
    aws = aws.localstack
  }

  project_name = var.project_name
  region       = var.region
}
