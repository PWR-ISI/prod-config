output "alb_dns" {
  value = aws_lb.alb.dns_name
}

output "db_endpoint" {
  value = aws_db_instance.file-upload.address
}

output "sns_topic_arn" {
  value = aws_sns_topic.file-upload_events.arn
}

output "sqs_queue_url" {
  value = aws_sqs_queue.file-upload_inbox.url
}

output "sqs_queue_arn" {
  value = aws_sqs_queue.file-upload_inbox.arn
}
