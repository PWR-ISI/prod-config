<#
.SYNOPSIS
    Marks an appointment as paid by simulating a PayU COMPLETED webhook.

.DESCRIPTION
    Fetches the appointment from schedule-service to retrieve its payment_order_id,
    then fires a fake PayU webhook at payment-service. Payment-service publishes
    payment.succeeded to SNS -> schedule-service SQS consumer flips the appointment
    to 'paid'.

.PARAMETER AppointmentId
    UUID of the appointment to mark as paid.

.PARAMETER Email
    Admin/doctor account used to fetch the appointment. Default: admin@isi.test

.PARAMETER Password
    Password for the account. Default: Admin123!

.EXAMPLE
    .\scripts\mark-paid.ps1 -AppointmentId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
#>
param(
    [Parameter(Mandatory)]
    [string]$AppointmentId,

    [string]$Email    = "admin@isi.test",
    [string]$Password = "Admin123!"
)

$AUTH     = "http://prod-config-auth-alb.elb.localhost.localstack.cloud:4566/api/v2"
$SCHEDULE = "http://prod-config-schedule-alb.elb.localhost.localstack.cloud:4566"
$PAYMENT  = "http://prod-config-payment-alb.elb.localhost.localstack.cloud:4566"

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# 1. Login
Write-Host "Logging in as $Email..."
$loginResp = Invoke-RestMethod `
    -Uri "$AUTH/auth/login/" `
    -Method Post `
    -ContentType "application/json" `
    -Body (@{ email = $Email; password = $Password } | ConvertTo-Json)
$token = $loginResp.access_token
if (-not $token) { Write-Error "Login failed - no access_token in response."; exit 1 }
$H = @{ Authorization = "Bearer $token" }

# 2. Fetch appointment
Write-Host "Fetching appointment $AppointmentId..."
$appt = Invoke-RestMethod `
    -Uri "$SCHEDULE/api/v1/appointments/$AppointmentId" `
    -Headers $H
$payuOrderId = $appt.payment_order_id

Write-Host "  status          : $($appt.status)"
Write-Host "  payment_order_id: $payuOrderId"

if ($appt.status -eq "paid") {
    Write-Host "Appointment is already paid. Nothing to do."
    exit 0
}

if ($payuOrderId) {
    # 3a. Payment order exists -- simulate PayU webhook via payment-service
    Write-Host "Sending PayU COMPLETED webhook for order $payuOrderId..."
    $webhookBody = @{
        order = @{
            orderId      = $payuOrderId
            orderStatus  = "COMPLETED"
            totalAmount  = "15000"
            currencyCode = "PLN"
        }
    } | ConvertTo-Json -Depth 3

    $webhookResp = Invoke-RestMethod `
        -Uri "$PAYMENT/api/payments/webhook" `
        -Method POST `
        -ContentType "application/json" `
        -Body $webhookBody `
        -Headers @{ "OpenPayU-Signature" = "sender=checkout;signature=skip;algorithm=MD5;content=DOCUMENT" }

    Write-Host "  webhook response: $($webhookResp | ConvertTo-Json -Compress)"
} else {
    # 3b. No payment order (PAYMENTS_ENABLED=false at booking time) -- inject event directly into SQS
    Write-Host "No payment_order_id found -- injecting payment.succeeded directly into schedule-service SQS..."
    $env:AWS_ACCESS_KEY_ID     = "test"
    $env:AWS_SECRET_ACCESS_KEY = "test"
    $env:AWS_DEFAULT_REGION    = "us-east-1"

    $sqsUrl = "http://sqs.us-east-1.localhost.localstack.cloud:4566/000000000000/prod-config-schedule-inbox"
    $eventMsg = @{
        event_type   = "payment.succeeded"
        event_id     = [guid]::NewGuid().ToString()
        occurred_at  = (Get-Date -Format "o")
        payload      = @{ appointment_id = $AppointmentId }
    } | ConvertTo-Json -Depth 3 -Compress

    aws sqs send-message `
        --queue-url $sqsUrl `
        --message-body $eventMsg `
        --endpoint-url http://localhost:4566 `
        --region us-east-1 | Out-Null
    Write-Host "  Event sent to SQS."
}

# 4. Poll until appointment flips to 'paid'
Write-Host "Waiting for schedule-service to process the event..."
$maxWait = 30
$waited  = 0
while ($waited -lt $maxWait) {
    Start-Sleep -Seconds 2
    $waited += 2
    $updated = Invoke-RestMethod -Uri "$SCHEDULE/api/v1/appointments/$AppointmentId" -Headers $H
    if ($updated.status -eq "paid") {
        Write-Host "Appointment $AppointmentId is now PAID."
        exit 0
    }
    Write-Host "  [$waited s] status still: $($updated.status)"
}

Write-Warning "Timed out after ${maxWait}s - appointment status is still '$($updated.status)'."
Write-Warning "The SQS consumer may be catching up. Check schedule-service logs."
exit 1