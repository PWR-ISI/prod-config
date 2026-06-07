variable "project_name" { type = string }
variable "region" { type = string }
variable "notification_email" {
  type    = string
  default = ""
  description = "Email address to subscribe to SNS notification topics"
}
