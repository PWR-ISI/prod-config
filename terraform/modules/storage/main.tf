variable "project_name" { type = string }
variable "region" { type = string }
variable "notification_email" {
  type    = string
  default = ""
}

# ── S3 bucket for file storage ─────────────────────────────────────────────
resource "aws_s3_bucket" "files" {
  bucket        = "${var.project_name}-files-${var.region}"
  force_destroy = true
}

resource "aws_s3_bucket_cors_configuration" "files" {
  bucket = aws_s3_bucket.files.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_public_access_block" "files" {
  bucket = aws_s3_bucket.files.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── SES email identity ─────────────────────────────────────────────────────
resource "aws_ses_email_identity" "sender" {
  count = var.notification_email != "" ? 1 : 0
  email = var.notification_email
}

# ── EventBridge Scheduler execution role ──────────────────────────────────
resource "aws_iam_role" "scheduler_exec" {
  name = "${var.project_name}-scheduler-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "scheduler_sqs" {
  role = aws_iam_role.scheduler_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sqs:SendMessage"
      Resource = "arn:aws:sqs:${var.region}:*:${var.project_name}-*"
    }]
  })
}

output "files_bucket_name" { value = aws_s3_bucket.files.id }
output "files_bucket_arn" { value = aws_s3_bucket.files.arn }
output "scheduler_exec_role_arn" { value = aws_iam_role.scheduler_exec.arn }
