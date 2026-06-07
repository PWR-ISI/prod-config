terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

variable "project_name" { type = string }
variable "region" { type = string }

resource "aws_s3_bucket" "frontend" {
  bucket = "${var.project_name}-frontend-${var.region}"
}

resource "aws_s3_bucket_ownership_controls" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  rule { object_ownership = "BucketOwnerPreferred" }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_acl" "frontend" {
  depends_on = [
    aws_s3_bucket_ownership_controls.frontend,
    aws_s3_bucket_public_access_block.frontend,
  ]
  bucket = aws_s3_bucket.frontend.id
  acl    = "public-read"
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document { suffix = "index.html" }
  error_document { key = "index.html" }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  depends_on = [aws_s3_bucket_public_access_block.frontend]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = ["s3:GetObject"]
      Resource  = ["${aws_s3_bucket.frontend.arn}/*"]
    }]
  })
}

resource "aws_s3_bucket_cors_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

output "bucket" {
  value = aws_s3_bucket.frontend.id
}

output "website_endpoint" {
  value = "http://${aws_s3_bucket.frontend.id}.s3-website-${var.region}.amazonaws.com"
}
