resource "aws_s3_bucket" "frontend_bucket" {
  bucket = "${var.project_name}-frontend"
  acl    = "public-read"

  website {
    index_document = "index.html"
    error_document = "index.html"
  }
}

resource "aws_s3_bucket_policy" "frontend_policy" {
  bucket = aws_s3_bucket.frontend_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = ["s3:GetObject"]
        Resource = ["${aws_s3_bucket.frontend_bucket.arn}/*"]
      }
    ]
  })
}
# (opcjonalnie) CloudFront distribution dla cache/HTTPS w prod — trudniejszy do emulacji w LocalStack

variable "project_name" {}
variable "region" {}