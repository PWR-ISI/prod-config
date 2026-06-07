# Appointment notifications topic
resource "aws_sns_topic" "appointment_notifications" {
  name = "${var.project_name}-appointment-notifications"
  tags = { Project = var.project_name }
}

# File upload notifications topic
resource "aws_sns_topic" "file_upload_notifications" {
  name = "${var.project_name}-file-upload-notifications"
  tags = { Project = var.project_name }
}

# Email subscription — uses variable instead of hardcoded address
resource "aws_sns_topic_subscription" "appointment_email" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.appointment_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

output "appointment_topic_arn" {
  value = aws_sns_topic.appointment_notifications.arn
}

output "file_upload_topic_arn" {
  value = aws_sns_topic.file_upload_notifications.arn
}
