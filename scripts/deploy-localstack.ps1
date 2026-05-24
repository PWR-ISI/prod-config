# ISI Medical System - LocalStack Fargate Deployment
# Windows PowerShell Script

param(
    [ValidateSet('build', 'push', 'deploy', 'clean', 'full')]
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

function Initialize-LocalStack {
    Write-Status "Initializing LocalStack (Cognito, SQS, SNS)..." "INFO"

    $env:AWS_ENDPOINT_URL = "http://localhost:4566"
    $env:AWS_ACCESS_KEY_ID = "test"
    $env:AWS_SECRET_ACCESS_KEY = "test"
    $env:AWS_DEFAULT_REGION = "us-east-1"

    # Run init script
    if (Test-Path "localstack-init/00-bootstrap.sh") {
        Write-Status "Running bootstrap script..." "INFO"
        docker exec prod-localstack bash /etc/localstack/init/ready.d/00-bootstrap.sh
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

        Write-Status "✓ $service built" "INFO"
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

        Write-Status "✓ $service pushed" "INFO"
    }

    Write-Status "All services pushed to ECR" "INFO"
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

    cd terraform

    # Initialize Terraform
    Write-Status "Initializing Terraform..." "INFO"
    terraform init

    # Plan
    Write-Status "Running Terraform plan..." "INFO"
    terraform plan -out=tfplan

    # Apply
    Write-Status "Applying Terraform configuration..." "INFO"
    terraform apply tfplan

    # Get outputs
    Write-Status "Terraform deployment complete!" "INFO"
    Write-Host ""
    Write-Status "Outputs:" "INFO"
    terraform output

    cd ..
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

    Write-Status "✓ Frontend deployed" "INFO"

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
