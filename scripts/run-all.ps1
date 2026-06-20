<#
  run-all.ps1  —  One-shot LocalStack deployment of the ISI medical system.

  Brings the whole stack up from scratch on LocalStack (emulated AWS):
  LocalStack -> Cognito/SQS bootstrap -> build 8 service images ->
  terraform apply (API GW, ALBs, RDS, ECS) -> push images to ECR ->
  roll ECS services -> seed slots -> build & deploy the frontend to S3.

  Run from anywhere (paths resolve relative to this script):
      cd "<...>\ISI\prod-config"
      .\scripts\run-all.ps1

  PREREQUISITES
    - Docker Desktop running
    - terraform, aws CLI on PATH
    - prod-config\.env contains  LOCALSTACK_AUTH_TOKEN=...   (LocalStack PRO)
    - frontend-portal\.env.production exists (points the SPA at the ALBs)

  Options:
    -SkipFrontend   don't build/deploy the React app
    -SkipSeed       don't seed appointment slots
    -SkipBuild      reuse already-built images (just apply + push + roll)

  Note: a full run is heavy (~20-40 min): 8 image builds + 7 RDS instances.
#>
param([switch]$SkipFrontend, [switch]$SkipSeed, [switch]$SkipBuild)

# NOTE: "Continue" (not "Stop") so native tools writing to stderr (docker/aws/terraform)
# don't abort the script under Windows PowerShell 5.1. Every critical step below has an
# explicit $LASTEXITCODE check / try-catch, so real failures are still caught.
$ErrorActionPreference = "Continue"

$ScriptDir  = $PSScriptRoot
$ProdConfig = Split-Path $ScriptDir  -Parent          # ...\ISI\prod-config
$Root       = $ProdConfig                             # monorepo: module sources live INSIDE prod-config
$Reg        = "000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:4566"

function Set-AwsEnv {
    $env:AWS_ENDPOINT_URL      = "http://localhost:4566"
    $env:AWS_ACCESS_KEY_ID     = "test"
    $env:AWS_SECRET_ACCESS_KEY = "test"
    $env:AWS_DEFAULT_REGION    = "us-east-1"
    $env:TF_VAR_aws_endpoint_url = "http://localhost:4566"
}

# service directory  ->  ECR repo name the ECS task definition references.
# (These names MUST match each terraform module's image string.)
$Services = [ordered]@{
    'auth-identity-service'  = 'prod-config-auth'
    'appointment-service'    = 'prod-config-core-repo'
    'schedule-service'       = 'prod-config-schedule-repo'
    'payment-service'        = 'prod-config-payment-repo'
    'notification-service'   = 'prod-config-notification'
    'facility-staff-service' = 'prod-config-facility'
    'medical-record-service' = 'prod-config-medical'
    'audit-logging-service'  = 'prod-config-audit'
}
# ECS cluster/service base names (cluster = "<base>-cluster", service = "<base>-svc")
$EcsBases = @('prod-config-auth','prod-config-core','prod-config-schedule','prod-config-payment',
              'prod-config-notification','prod-config-facility','prod-config-medical','prod-config-audit')

# ---------------------------------------------------------------------------
Write-Host "=== [1/8] Start LocalStack ============================" -ForegroundColor Cyan
Push-Location $ProdConfig
docker compose up -d
Write-Host "  waiting for LocalStack to be healthy..."
$healthy = $false
for ($i = 0; $i -lt 60; $i++) {
    if ((docker inspect -f '{{.State.Health.Status}}' prod-localstack 2>$null) -eq 'healthy') { $healthy = $true; break }
    Start-Sleep -Seconds 2
}
Pop-Location
if (-not $healthy) { throw "LocalStack never became healthy — check LOCALSTACK_AUTH_TOKEN in prod-config\.env" }

# ---------------------------------------------------------------------------
Write-Host "=== [2/8] Bootstrap Cognito + SQS =====================" -ForegroundColor Cyan
Set-AwsEnv
# ids.env survives a volume wipe but its IDs may be stale — drop it so the script re-seeds.
if (Test-Path "$ProdConfig\localstack-init\ids.env") { Remove-Item "$ProdConfig\localstack-init\ids.env" -Force }
docker exec prod-localstack bash //etc/localstack/init/ready.d/00-bootstrap.sh

# ---------------------------------------------------------------------------
if (-not $SkipBuild) {
    Write-Host "=== [3/8] Build + tag 8 service images ============" -ForegroundColor Cyan
    foreach ($svc in $Services.Keys) {
        $img = "$Reg/$($Services[$svc]):latest"
        Write-Host "  building $svc -> $img"
        docker build -t $img (Join-Path $Root $svc)
        if ($LASTEXITCODE -ne 0) { throw "docker build failed: $svc" }
    }
} else { Write-Host "=== [3/8] (skipped image build) ===" -ForegroundColor DarkGray }

# ---------------------------------------------------------------------------
Write-Host "=== [4/8] terraform apply (infra) =====================" -ForegroundColor Cyan
Set-AwsEnv
Push-Location "$ProdConfig\terraform"
terraform init | Out-Null
terraform apply -auto-approve -no-color
if ($LASTEXITCODE -ne 0) {
    # LocalStack PRO has an intermittent RDS-SSL race; a second apply usually settles it.
    Write-Host "  first apply failed (likely the RDS-SSL race) — retrying in 10s..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    terraform apply -auto-approve -no-color
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw "terraform apply failed twice" }
}
Pop-Location

# ---------------------------------------------------------------------------
Write-Host "=== [5/8] Create ECR repos + push images ==============" -ForegroundColor Cyan
Set-AwsEnv
# IMPORTANT: push to the real ECR registry host with docker login.
# Pushing to "localhost:4566" hits LocalStack's generic edge and fails with
# "received unexpected HTTP status: 200 OK".
aws ecr get-login-password --region us-east-1 --endpoint-url http://localhost:4566 |
    docker login --username AWS --password-stdin $Reg | Out-Null
foreach ($svc in $Services.Keys) {
    $repo = $Services[$svc]
    # terraform creates the "*-repo" repos; create the others (auth/notification/facility/medical/audit).
    aws ecr create-repository --repository-name $repo --endpoint-url http://localhost:4566 2>$null | Out-Null
    docker push "$Reg/${repo}:latest"
    if ($LASTEXITCODE -ne 0) { throw "docker push failed: $repo" }
}

# ---------------------------------------------------------------------------
Write-Host "=== [6/8] Roll ECS services (pull fresh images) =======" -ForegroundColor Cyan
foreach ($base in $EcsBases) {
    try {
        aws ecs update-service --cluster "$base-cluster" --service "$base-svc" `
            --force-new-deployment --endpoint-url http://localhost:4566 `
            --query "service.serviceName" --output text 2>$null | Out-Null
    } catch { }
}
Write-Host "  waiting 90s for tasks to start + migrate..."
Start-Sleep -Seconds 90

# ---------------------------------------------------------------------------
if (-not $SkipSeed) {
    Write-Host "=== [7/8] Seed appointment slots ==================" -ForegroundColor Cyan
    $cid = ("" + (docker ps --format "{{.Names}}" | Select-String "prod-config-schedule-cluster" | Select-Object -First 1)).Trim()
    if ($cid) { docker exec $cid python manage.py seed_slots } else { Write-Host "  (schedule container not found yet — run seed_slots manually later)" -ForegroundColor Yellow }
} else { Write-Host "=== [7/8] (skipped slot seeding) ===" -ForegroundColor DarkGray }

# ---------------------------------------------------------------------------
if (-not $SkipFrontend) {
    Write-Host "=== [8/8] Build + deploy frontend to S3 ===========" -ForegroundColor Cyan
    $fe = Join-Path $Root "frontend-portal"
    docker build --target build -t isi-frontend-build $fe       # multi-stage: builds /app/dist
    docker rm -f fe-extract 2>$null | Out-Null
    docker create --name fe-extract isi-frontend-build | Out-Null
    if (Test-Path "$fe\dist") { Remove-Item -Recurse -Force "$fe\dist" }
    docker cp fe-extract:/app/dist "$fe\dist"
    docker rm fe-extract | Out-Null
    aws s3 sync "$fe\dist" s3://prod-config-frontend --delete --endpoint-url http://localhost:4566 | Out-Null
} else { Write-Host "=== [8/8] (skipped frontend) ===" -ForegroundColor DarkGray }

# ---------------------------------------------------------------------------
Write-Host "`n================  DEPLOYMENT COMPLETE  ================" -ForegroundColor Green
Write-Host "Frontend:     http://prod-config-frontend.s3-website.localhost.localstack.cloud:4566"
Write-Host "Auth (ALB):   http://prod-config-auth-alb.elb.localhost.localstack.cloud:4566/api/v2/health/"
Write-Host "Schedule(ALB):http://prod-config-schedule-alb.elb.localhost.localstack.cloud:4566/health/"
Write-Host "`nLogin/Register from the frontend. New accounts land in the Cognito pool the auth service uses."
