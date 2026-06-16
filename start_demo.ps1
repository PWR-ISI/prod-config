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

Write-Host "==> 4/5  Czekam az serwisy wstana..." -ForegroundColor Cyan
Start-Sleep -Seconds 12

Write-Host "==> 5/5  Seeduje dane demo (powiadomienia + dokumenty medyczne)..." -ForegroundColor Cyan
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
