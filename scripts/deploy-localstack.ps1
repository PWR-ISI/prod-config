# ISI Medical System - LocalStack Fargate Deployment
# Windows PowerShell Script
#
# Actions:
#   reset  - Full wipe: stop containers, delete LocalStack volume + Terraform
#            state, restart clean. Use when LocalStack state drifted or after
#            "docker compose restart" left ELB/ECS in an inconsistent place.
#   apply  - terraform apply against an already-running LocalStack. Includes
#            automatic retry for the intermittent RDS-SSL-PEM race in
#            LocalStack Pro (re-runs `-replace` on any DB stuck in `error`).
#   deploy - start LocalStack + initialize + apply. Skips image build/push.
#   build  - docker build of all service images.
#   push   - create ECR repos and push images (call after build).
#   clean  - terraform destroy + docker compose down (preserves volume).
#   full   - start + init + build + push + apply + frontend deploy.

param(
    [ValidateSet('build', 'push', 'deploy', 'clean', 'reset', 'apply', 'full')]
    [string]$Action = 'full'
)

$ErrorActionPreference = "Stop"

# Colors
$Green = 'Green'
$Yellow = 'Yellow'
$Red = 'Red'

function Write-Status {
    param([string]$Message, [string]$Status = "INFO")
    $Color = $Green
    if ($Status -eq "WARN") { $Color = $Yellow }
    if ($Status -eq "ERROR") { $Color = $Red }
    Write-Host "[$Status] $Message" -ForegroundColor $Color
}

function Check-Prerequisites {
    Write-Status "Checking prerequisites..." "INFO"

    $required = @('docker', 'aws', 'terraform')
    foreach ($cmd in $required) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            Write-Status "Missing: $cmd" "ERROR"
            exit 1
        }
    }

    Write-Status "All prerequisites OK" "INFO"
}

function Start-LocalStack {
    Write-Status "Starting LocalStack..." "INFO"

    # Check if already running
    $running = docker ps --filter "name=prod-localstack" --filter "status=running" -q

    if ($running) {
        Write-Status "LocalStack already running" "WARN"
    } else {
        Write-Status "Starting LocalStack container..." "INFO"
        docker-compose up -d

        Write-Status "Waiting for LocalStack to be healthy..." "INFO"
        $maxRetries = 30
        $retries = 0

        while ($retries -lt $maxRetries) {
            $health = docker ps --filter "name=prod-localstack" --filter "health=healthy" -q
            if ($health) {
                Write-Status "LocalStack is healthy" "INFO"
                break
            }

            $retries++
            Start-Sleep -Seconds 2
            Write-Host "." -NoNewline
        }

        if ($retries -eq $maxRetries) {
            Write-Status "LocalStack failed to start" "ERROR"
            exit 1
        }

        Write-Host ""
    }
}

function Set-LocalStackEnv {
    $env:AWS_ENDPOINT_URL = "http://localhost:4566"
    $env:AWS_ACCESS_KEY_ID = "test"
    $env:AWS_SECRET_ACCESS_KEY = "test"
    $env:AWS_DEFAULT_REGION = "us-east-1"
}

function Initialize-LocalStack {
    Write-Status "Initializing LocalStack (Cognito, SQS, SNS)..." "INFO"

    Set-LocalStackEnv

    # The bootstrap script writes ids.env (Cognito pool id, SQS URLs) and
    # short-circuits on subsequent runs by checking that file. After a volume
    # wipe, the file persists on the host mount even though the IDs it
    # references no longer exist in LocalStack. Delete it so the bootstrap
    # actually re-seeds.
    if (Test-Path "localstack-init/ids.env") {
        Remove-Item "localstack-init/ids.env" -Force
    }

    if (Test-Path "localstack-init/00-bootstrap.sh") {
        Write-Status "Running bootstrap script..." "INFO"
        # Leading // prevents Git Bash from mangling the path on Windows.
        docker exec prod-localstack bash //etc/localstack/init/ready.d/00-bootstrap.sh
    }
}

function Build-Services {
    Write-Status "Building Docker images for all services..." "INFO"

    $services = @(
        'auth-identity-service',
        'appointment-service',
        'schedule-service',
        'payment-service',
        'notification-service',
        'facility-staff-service',
        'medical-record-service',
        'audit-logging-service',
        'frontend-portal'
    )

    foreach ($service in $services) {
        Write-Status "Building $service..." "INFO"

        if ($service -eq 'frontend-portal') {
            # Frontend builds differently
            docker build -t "localhost:4566/isi-$service`:latest" -f "$service/Dockerfile" $service
        } else {
            docker build -t "localhost:4566/isi-$service`:latest" $service
        }

        if ($LASTEXITCODE -ne 0) {
            Write-Status "Failed to build $service" "ERROR"
            exit 1
        }

        Write-Status "[OK]$service built" "INFO"
    }

    Write-Status "All services built successfully" "INFO"
}

function Push-ToECR {
    Write-Status "Creating ECR repositories in LocalStack..." "INFO"

    $env:AWS_ENDPOINT_URL = "http://localhost:4566"
    $env:AWS_ACCESS_KEY_ID = "test"
    $env:AWS_SECRET_ACCESS_KEY = "test"
    $env:AWS_DEFAULT_REGION = "us-east-1"

    $services = @(
        'auth-identity-service',
        'appointment-service',
        'schedule-service',
        'payment-service',
        'notification-service',
        'facility-staff-service',
        'medical-record-service',
        'audit-logging-service',
        'frontend-portal'
    )

    foreach ($service in $services) {
        $repoName = "isi-$service"

        # Create ECR repository
        Write-Status "Creating ECR repo: $repoName" "INFO"
        aws ecr create-repository --repository-name $repoName --endpoint-url $env:AWS_ENDPOINT_URL 2>$null

        # Push image
        Write-Status "Pushing $service to ECR..." "INFO"
        docker tag "localhost:4566/$repoName`:latest" "localhost:4566/$repoName`:latest"
        docker push "localhost:4566/$repoName`:latest"

        Write-Status "[OK]$service pushed" "INFO"
    }

    Write-Status "All services pushed to ECR" "INFO"
}

function Reset-FullState {
    Write-Status "RESET: full LocalStack + Terraform state wipe" "WARN"

    # Stop and remove LocalStack container so the volume is unlocked.
    docker compose down 2>$null | Out-Null

    # Volume wipe: the SSL PEM bug in LocalStack postgres-proxy comes from a
    # corrupted CA cert at cache/certs/ca/ — removing the whole volume forces
    # a regeneration on next start.
    if (Test-Path "localstack-data") {
        Remove-Item -Recurse -Force "localstack-data"
        Write-Status "Removed localstack-data/" "INFO"
    }

    # Terraform state must match LocalStack reality. After a volume wipe
    # nothing in state is valid; refresh would fail with stale ARNs.
    Remove-Item -Force "terraform/terraform.tfstate", "terraform/terraform.tfstate.backup", "terraform/tfplan" -ErrorAction SilentlyContinue
    Write-Status "Removed terraform.tfstate*" "INFO"

    # ids.env on the host mount survives the volume wipe; remove it so the
    # bootstrap re-seeds Cognito/SQS on next start.
    Remove-Item -Force "localstack-init/ids.env" -ErrorAction SilentlyContinue

    Write-Status "Reset complete. Run with -Action deploy to bring the stack back up." "INFO"
}

function Invoke-RdsRetry {
    # The LocalStack Pro RDS shim has a race in postgres-proxy SSL setup that
    # leaves ~1/7 instances in `status=error` on a cold apply. Detect those,
    # delete them in LocalStack, and -replace the matching Terraform resource.
    # Idempotent: zero error DBs → no-op.
    Set-LocalStackEnv

    $errored = aws rds describe-db-instances `
        --endpoint-url http://localhost:4566 `
        --query "DBInstances[?DBInstanceStatus=='error'].DBInstanceIdentifier" `
        --output text 2>$null

    if (-not $errored) {
        return $true
    }

    Write-Status "Found RDS instances in 'error' state: $errored" "WARN"

    # Map LocalStack DB-name → terraform resource. The instances created by
    # Terraform have auto-generated identifiers (terraform-<random>) so we
    # join on DBName instead.
    $rdsToModule = @{
        "authdb"     = "module.auth_service.aws_db_instance.auth"
        "coredb"     = "module.appointment_service.aws_db_instance.core"
        "scheduledb" = "module.schedule_service.aws_db_instance.schedule"
        "payment_db" = "module.payment_service.aws_db_instance.payment"
        "facilitydb" = "module.facility_service.aws_db_instance.facility"
        "medicaldb"  = "module.medical_service.aws_db_instance.medical"
        "auditdb"    = "module.audit_service.aws_db_instance.audit"
    }

    $replaceArgs = @()
    foreach ($id in ($errored -split '\s+' | Where-Object { $_ })) {
        $dbName = aws rds describe-db-instances `
            --endpoint-url http://localhost:4566 `
            --db-instance-identifier $id `
            --query "DBInstances[0].DBName" `
            --output text 2>$null

        if ($rdsToModule.ContainsKey($dbName)) {
            Write-Status "Will replace: $($rdsToModule[$dbName]) (DBName=$dbName)" "INFO"
            $replaceArgs += "-replace=$($rdsToModule[$dbName])"

            # Pre-delete so terraform's create succeeds with a clean slate.
            aws rds delete-db-instance --endpoint-url http://localhost:4566 `
                --db-instance-identifier $id --skip-final-snapshot 2>$null | Out-Null
        }
    }

    if ($replaceArgs.Count -eq 0) {
        return $true
    }

    Write-Status "Retrying failed RDS via -target=module.X with -replace..." "INFO"
    Push-Location terraform
    try {
        $targets = $replaceArgs | ForEach-Object { $_ -replace '^-replace=(.*)\.aws_db_instance\..*$', '-target=$1' } | Sort-Object -Unique
        $allArgs = @('apply', '-auto-approve', '-no-color') + $replaceArgs + $targets
        & terraform @allArgs
        return ($LASTEXITCODE -eq 0)
    }
    finally {
        Pop-Location
    }
}

function Deploy-Terraform {
    Write-Status "Deploying infrastructure with Terraform..." "INFO"

    # Set environment variables for Terraform
    $env:AWS_ENDPOINT_URL = "http://localhost:4566"
    $env:AWS_ACCESS_KEY_ID = "test"
    $env:AWS_SECRET_ACCESS_KEY = "test"
    $env:AWS_DEFAULT_REGION = "us-east-1"
    $env:TF_VAR_aws_endpoint_url = "http://localhost:4566"
    $env:TF_VAR_docker_image_uri_auth = "localhost:4566/isi-auth-identity-service:latest"
    $env:TF_VAR_docker_image_uri_appointment = "localhost:4566/isi-appointment-service:latest"
    $env:TF_VAR_docker_image_uri_schedule = "localhost:4566/isi-schedule-service:latest"
    $env:TF_VAR_docker_image_uri_payment = "localhost:4566/isi-payment-service:latest"
    $env:TF_VAR_docker_image_uri_notification = "localhost:4566/isi-notification-service:latest"
    $env:TF_VAR_docker_image_uri_facility = "localhost:4566/isi-facility-staff-service:latest"
    $env:TF_VAR_docker_image_uri_medical = "localhost:4566/isi-medical-record-service:latest"
    $env:TF_VAR_docker_image_uri_audit = "localhost:4566/isi-audit-logging-service:latest"
    $env:TF_VAR_docker_image_uri_frontend = "localhost:4566/isi-frontend-portal:latest"

    Push-Location terraform
    try {
        Write-Status "Initializing Terraform..." "INFO"
        terraform init | Out-Null

        # First apply: -auto-approve, no separate plan file. We tolerate a
        # single failure here because the LocalStack RDS SSL race typically
        # only hits 1/7 instances; we retry just the failed ones below.
        Write-Status "Applying Terraform configuration..." "INFO"
        terraform apply -auto-approve -no-color

        if ($LASTEXITCODE -ne 0) {
            Write-Status "First apply failed; checking for retriable RDS errors..." "WARN"
            Pop-Location
            $rdsOk = Invoke-RdsRetry
            Push-Location terraform

            if (-not $rdsOk) {
                Write-Status "RDS retry failed. Inspect LocalStack logs: docker logs prod-localstack | Select-String -Pattern 'SSL|PEM|error'" "ERROR"
                exit 1
            }

            # Re-run full apply to settle the rest of the graph after the
            # targeted RDS retry.
            Write-Status "Re-running full apply to settle remaining resources..." "INFO"
            terraform apply -auto-approve -no-color
            if ($LASTEXITCODE -ne 0) {
                Write-Status "Apply still failing after RDS retry. Stop and inspect." "ERROR"
                exit 1
            }
        }

        Write-Status "Terraform deployment complete!" "INFO"
        Write-Host ""
        Write-Status "Outputs:" "INFO"
        terraform output
    }
    finally {
        Pop-Location
    }
}

function Deploy-Frontend {
    Write-Status "Deploying frontend to S3..." "INFO"

    $env:AWS_ENDPOINT_URL = "http://localhost:4566"

    cd frontend-portal

    # Build frontend
    Write-Status "Building frontend..." "INFO"
    npm run build

    # Upload to S3
    Write-Status "Uploading to S3..." "INFO"
    $bucket = "isi-prod-frontend"

    aws s3 mb "s3://$bucket" --endpoint-url $env:AWS_ENDPOINT_URL 2>$null
    aws s3 sync dist "s3://$bucket" --endpoint-url $env:AWS_ENDPOINT_URL

    Write-Status "[OK]Frontend deployed" "INFO"

    cd ..
}

function Clean-Deployment {
    Write-Status "Cleaning up deployment..." "INFO"

    cd terraform
    terraform destroy -auto-approve
    cd ..

    Write-Status "Terraform destroyed" "INFO"

    Write-Status "Stopping LocalStack..." "INFO"
    docker-compose down -v

    Write-Status "Cleanup complete" "INFO"
}

# Main flow
Write-Status "=== ISI Medical System - LocalStack Deployment ===" "INFO"

Check-Prerequisites

switch ($Action) {
    'build' {
        Start-LocalStack
        Build-Services
    }
    'push' {
        Start-LocalStack
        Initialize-LocalStack
        Push-ToECR
    }
    'apply' {
        # Assumes LocalStack is already up. Use this for the inner-dev loop
        # when iterating on .tf files.
        Set-LocalStackEnv
        Deploy-Terraform
    }
    'reset' {
        Reset-FullState
        Start-LocalStack
        Initialize-LocalStack
        Deploy-Terraform
    }
    'deploy' {
        Start-LocalStack
        Initialize-LocalStack
        Deploy-Terraform
    }
    'clean' {
        Clean-Deployment
    }
    'full' {
        Start-LocalStack
        Initialize-LocalStack
        Build-Services
        Push-ToECR
        Deploy-Terraform
        Deploy-Frontend
    }
}

Write-Status "=== Deployment Complete ===" "INFO"
Write-Status "Access services:" "INFO"
Write-Host "Frontend: http://localhost:3000"
Write-Host "Auth API: http://localhost:8001/api/v2/"
Write-Host "Appointment API: http://localhost:8002/api/v2/"
Write-Host "API Gateway: Check terraform output for URL"
Write-Host ""
