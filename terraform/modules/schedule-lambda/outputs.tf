output "api_endpoint"   { value = aws_apigatewayv2_api.schedule.api_endpoint }
output "sns_topic_arn"  { value = aws_sns_topic.schedule_events.arn }
output "sqs_queue_arn"  { value = aws_sqs_queue.schedule_inbox.arn }
output "sqs_queue_url"  { value = aws_sqs_queue.schedule_inbox.url }
output "db_endpoint"    { value = aws_db_instance.schedule.address }
output "function_names" { value = { for k, fn in aws_lambda_function.schedule : k => fn.function_name } }
