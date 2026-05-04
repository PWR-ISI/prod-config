resource "aws_dynamodb_table" "notifications" {
  name           = "${var.project_name}-notifications"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "notificationId"

  attribute {
    name = "notificationId"
    type = "S"
  }

  tags = {
    Service = "notification"
  }
}

variable "project_name" {}
variable "region" {}