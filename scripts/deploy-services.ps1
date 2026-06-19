param(
    [string]$Region = "us-east-1"
)

$AccountId = aws sts get-caller-identity --query Account --output text

$Services = @{
    "auth-identity-service" = "isi-prod-auth"
    "appointment-service" = "isi-prod-core"
    "schedule-service" = "isi-prod-schedule"
    "payment-service" = "isi-prod-payment"
    "notification-service" = "isi-prod-notification"
    "facility-staff-service" = "isi-prod-facility"
    "medical-record-service" = "isi-prod-medical"
    "audit-logging-service" = "isi-prod-audit"
}

Write-Host "Pushing services to ECR (Account: $AccountId, Region: $Region)" -ForegroundColor Green

aws ecr get-login-password --region $Region | docker login --username AWS --password-stdin "$AccountId.dkr.ecr.$Region.amazonaws.com" | Out-Null

foreach ($service in $Services.Keys) {
    if (Test-Path $service) {
        $repoBase = $Services[$service]
        $repo = "$repoBase-repo"
        $image = "$AccountId.dkr.ecr.$Region.amazonaws.com/$repo`:latest"

        Write-Host "Building $service..." -ForegroundColor Cyan
        docker build -t $image $service 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Built" -ForegroundColor Green
            Write-Host "Pushing $image..." -ForegroundColor Cyan
            docker push $image 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✓ Pushed" -ForegroundColor Green
            } else {
                Write-Host "✗ Push failed" -ForegroundColor Red
            }
        } else {
            Write-Host "✗ Build failed" -ForegroundColor Red
        }
    }
}

Write-Host "Done" -ForegroundColor Green
