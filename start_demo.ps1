# =====================================================================
#  ISI Medical System - uruchomienie wersji DEMO do prezentacji
#  Uruchom z katalogu prod-config:   .\start_demo.ps1
#  Wymaga: Docker Desktop uruchomiony.
# =====================================================================
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
Set-Location $root

Write-Host "==> 1/5  Start LocalStack..." -ForegroundColor Cyan
docker compose up -d | Out-Null

Write-Host "==> 2/5  Czekam az LocalStack bedzie zdrowy..." -ForegroundColor Cyan
for ($i = 0; $i -lt 30; $i++) {
    $h = (docker inspect --format='{{.State.Health.Status}}' prod-localstack 2>$null)
    if ($h -eq "healthy") { break }
    Start-Sleep -Seconds 4
}
Write-Host "    LocalStack: $h"

Write-Host "==> 3/5  Start mikroserwisow..." -ForegroundColor Cyan
$services = @(
    "auth-identity-service", "appointment-service", "schedule-service",
    "facility-staff-service", "medical-record-service", "notification-service"
)
foreach ($s in $services) {
    Push-Location (Join-Path $root $s)
    docker compose up -d | Out-Null
    Pop-Location
    Write-Host "    $s OK"
}

Write-Host "==> 4/6  Czekam az serwisy wstana..." -ForegroundColor Cyan
Start-Sleep -Seconds 12

Write-Host "==> 5/6  Konfiguruje zdarzenia SNS->SQS i startuje konsumenta powiadomien..." -ForegroundColor Cyan
# LocalStack nie zapisuje SNS/SQS po restarcie - odtwarzamy temat, kolejke i subskrypcje.
docker exec prod-localstack bash -c '
awslocal sqs create-queue --queue-name notification-jobs >/dev/null 2>&1
QURL=$(awslocal sqs get-queue-url --queue-name notification-jobs --query QueueUrl --output text)
QARN=$(awslocal sqs get-queue-attributes --queue-url "$QURL" --attribute-names QueueArn --query Attributes.QueueArn --output text)
TARN=$(awslocal sns create-topic --name notifications --query TopicArn --output text)
awslocal sqs set-queue-attributes --queue-url "$QURL" --attributes "{\"Policy\":\"{\\\"Version\\\":\\\"2012-10-17\\\",\\\"Statement\\\":[{\\\"Effect\\\":\\\"Allow\\\",\\\"Principal\\\":\\\"*\\\",\\\"Action\\\":\\\"sqs:SendMessage\\\",\\\"Resource\\\":\\\"$QARN\\\"}]}\"}" >/dev/null 2>&1
awslocal sns subscribe --topic-arn "$TARN" --protocol sqs --notification-endpoint "$QARN" >/dev/null 2>&1
echo "    SNS topic + SQS notification-jobs + subskrypcja OK"
'
# Konsument zdarzen: zamienia zdarzenia (np. appointment.created) na powiadomienia.
docker exec -d notification-service python manage.py consume_events
Write-Host "    Konsument powiadomien uruchomiony"

Write-Host "==> 6/6  Seeduje dane demo (powiadomienia + dokumenty medyczne)..." -ForegroundColor Cyan
docker exec medical-record-service python seed_demo.py
docker exec notification-service python seed_demo.py

Write-Host ""
Write-Host "===================================================================" -ForegroundColor Green
Write-Host " GOTOWE. Teraz uruchom frontend w osobnym oknie:" -ForegroundColor Green
Write-Host "   cd frontend-portal ; npm run dev" -ForegroundColor Yellow
Write-Host ""
Write-Host " Aplikacja:  http://localhost:3000" -ForegroundColor Yellow
Write-Host " Logowanie:  patient@example.com / Patient123!" -ForegroundColor Yellow
Write-Host "===================================================================" -ForegroundColor Green
