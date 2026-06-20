output "queue_arns" {
  description = "SQS queue ARNs keyed by service name"
  value = {
    for service, queue in aws_sqs_queue.service :
    service => queue.arn
  }
}

output "queue_urls" {
  description = "SQS queue URLs keyed by service name"
  value = {
    for service, queue in aws_sqs_queue.service :
    service => queue.id
  }
}

output "dlq_arns" {
  description = "SQS DLQ ARNs keyed by service name"
  value = {
    for service, queue in aws_sqs_queue.service_dlq :
    service => queue.arn
  }
}
