# File metadata table
resource "aws_dynamodb_table" "file_metadata" {
  name           = "${var.project_name}-file-metadata"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "file_id"
  range_key      = "created_at"

  attribute {
    name = "file_id"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "N"
  }

  attribute {
    name = "user_id"
    type = "S"
  }

  global_secondary_index {
    name            = "user-id-index"
    hash_key        = "user_id"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "expiration"
    enabled        = true
  }

  tags = {
    Project = var.project_name
  }
}

# Notification history table
resource "aws_dynamodb_table" "notification_history" {
  name           = "${var.project_name}-notifications"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "user_id"
  range_key      = "timestamp"

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  ttl {
    attribute_name = "expiration"
    enabled        = true
  }

  tags = {
    Project = var.project_name
  }
}

output "file_metadata_table_name" {
  value = aws_dynamodb_table.file_metadata.name
}

output "notification_history_table_name" {
  value = aws_dynamodb_table.notification_history.name
}
