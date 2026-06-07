# Import blocks for resources created via AWS CLI (now managed by Terraform)
# Run `terraform apply` after adding these — they'll be imported on first apply.

import {
  to = module.storage.aws_s3_bucket.files
  id = "isi-prod-files-us-east-1"
}

import {
  to = module.storage.aws_iam_role.scheduler_exec
  id = "isi-prod-scheduler-exec"
}

import {
  to = module.notification_service.aws_ecr_repository.notification
  id = "isi-prod-notification-repo"
}

import {
  to = module.notification_service.aws_dynamodb_table.notifications
  id = "isi-prod-notifications"
}
