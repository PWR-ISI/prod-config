# ISI Prod-Config AWS Deployment Script
# PowerShell version for Windows

param(
    [ValidateSet("full", "plan", "apply", "build-push", "update-services", "verify")]
    [string]$Mode = "full"
)

$ErrorActionPreference = "Stop"

function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Error_ { Write-Host $args -ForegroundColor Red }
function Write-Warning_ { Write-Host $args -ForegroundColor Yellow }
function Write-Info { Write-Host $args -ForegroundColor Cyan }

function Check-Prerequisites {
    Write-Info "Checking prerequisites..."

    $missing = @()

    if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) { $missing += "Terraform" }
    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) { $missing += "AWS CLI" }
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { $missing += "Docker" }

    if ($missing.Count -gt 0) {
        Write-Error_ "Missing tools: $($missing -join ', ')"
        exit 1
    }

    Write-Success "All prerequisites met"
    Write-Host ""
}

function Get-AWSInfo {
    Write-Info "Getting AWS information..."

    try {
        $script:AccountId = aws sts get-caller-identity --query Account --output text
        $script:Region = aws configure get region
        if (-not $script:Region) { $script:Region = "us-east-1" }

        Write-Success "AWS Account ID: $script:AccountId"
        Write-Success "AWS Region: $script:Region"
    }
    catch {
        Write-Error_ "Failed to get AWS info: $_"
        exit 1
    }
    Write-Host ""
}

function Build-And-Push-Images {
    Write-Info "Building and pushing Docker images..."
    Write-Host ""

    try {
        # Login to ECR
        Write-Info "Logging in to ECR..."
        $loginCmd = aws ecr get-login-password --region $script:Region
        $loginCmd | docker login --username AWS --password-stdin "$($script:AccountId).dkr.ecr.$($script:Region).amazonaws.com"

        # Schedule Service
        Write-Info "Building schedule-service..."
        Push-Location schedule-service
        docker build -t isi-prod-schedule:latest .
        docker tag isi-prod-schedule:latest "$($script:AccountId).dkr.ecr.$($script:Region).amazonaws.com/isi-prod-schedule-repo:latest"
        docker push "$($script:AccountId).dkr.ecr.$($script:Region).amazonaws.com/isi-prod-schedule-repo:latest"
        Pop-Location
        Write-Success "Schedule service pushed"
        Write-Host ""

        # File Upload Service
        Write-Info "Building file-upload-service..."
        Push-Location file-upload-service
        docker build -t isi-prod-file-upload:latest .
        docker tag isi-prod-file-upload:latest "$($script:AccountId).dkr.ecr.$($script:Region).amazonaws.com/isi-prod-file-upload-repo:latest"
        docker push "$($script:AccountId).dkr.ecr.$($script:Region).amazonaws.com/isi-prod-file-upload-repo:latest"
        Pop-Location
        Write-Success "File upload service pushed"
        Write-Host ""
    }
    catch {
        Write-Error_ "Failed to build/push images: $_"
        exit 1
    }
}

function Terraform-Init {
    Write-Info "Initializing Terraform..."

    try {
        Push-Location terraform
        terraform init
        Pop-Location
        Write-Success "Terraform initialized"
    }
    catch {
        Write-Error_ "Terraform init failed: $_"
        exit 1
    }
    Write-Host ""
}

function Terraform-Plan {
    Write-Info "Planning Terraform changes..."

    try {
        Push-Location terraform
        terraform plan -out=tfplan
        Pop-Location
        Write-Success "Terraform plan complete"
    }
    catch {
        Write-Error_ "Terraform plan failed: $_"
        exit 1
    }
    Write-Host ""
}

function Terraform-Apply {
    Write-Warning_ "Ready to apply Terraform changes"
    $response = Read-Host "Continue? (yes/no)"

    if ($response -ne "yes") {
        Write-Info "Skipping Terraform apply"
        return
    }

    try {
        Push-Location terraform
        terraform apply tfplan

        Write-Info "Saving outputs..."
        terraform output | Out-File -FilePath terraform-outputs.txt
        Write-Success "Outputs saved to terraform-outputs.txt"
        Pop-Location
    }
    catch {
        Write-Error_ "Terraform apply failed: $_"
        exit 1
    }
    Write-Host ""
}

function Update-ECS-Services {
    Write-Info "Updating ECS services..."

    try {
        Write-Info "Updating schedule-service..."
        aws ecs update-service `
            --cluster isi-prod-schedule-cluster `
            --service isi-prod-schedule-svc `
            --force-new-deployment `
            --region $script:Region | Out-Null
        Write-Success "Schedule service update initiated"

        Write-Info "Updating file-upload-service..."
        aws ecs update-service `
            --cluster isi-prod-file-upload-cluster `
            --service isi-prod-file-upload-svc `
            --force-new-deployment `
            --region $script:Region | Out-Null
        Write-Success "File upload service update initiated"
    }
    catch {
        Write-Error_ "Failed to update services: $_"
        exit 1
    }
    Write-Host ""
}

function Wait-For-Services {
    Write-Info "Waiting for services to stabilize (this may take 2-3 minutes)..."

    try {
        Write-Info "Waiting for schedule-service..."
        aws ecs wait services-stable `
            --cluster isi-prod-schedule-cluster `
            --services isi-prod-schedule-svc `
            --region $script:Region
        Write-Success "Schedule service is stable"

        Write-Info "Waiting for file-upload-service..."
        aws ecs wait services-stable `
            --cluster isi-prod-file-upload-cluster `
            --services isi-prod-file-upload-svc `
            --region $script:Region
        Write-Success "File upload service is stable"
    }
    catch {
        Write-Error_ "Services failed to stabilize: $_"
        # Don't exit - verification might still work
    }
    Write-Host ""
}

function Verify-Services {
    Write-Info "Verifying service deployments..."
    Write-Host ""

    try {
        Write-Host "Schedule Service Status:"
        aws ecs describe-services `
            --cluster isi-prod-schedule-cluster `
            --services isi-prod-schedule-svc `
            --region $script:Region `
            --query 'services[0].{Status:status,RunningCount:runningCount,DesiredCount:desiredCount}' `
            --output table

        Write-Host ""
        Write-Host "File Upload Service Status:"
        aws ecs describe-services `
            --cluster isi-prod-file-upload-cluster `
            --services isi-prod-file-upload-svc `
            --region $script:Region `
            --query 'services[0].{Status:status,RunningCount:runningCount,DesiredCount:desiredCount}' `
            --output table
    }
    catch {
        Write-Error_ "Verification failed: $_"
    }
    Write-Host ""
}

# Main execution
function Main {
    Write-Host "================================"
    Write-Host "ISI Prod-Config AWS Deployment"
    Write-Host "================================"
    Write-Host ""

    Check-Prerequisites
    Get-AWSInfo

    switch ($Mode) {
        "full" {
            Write-Info "Starting FULL deployment (plan + apply + build + push)"
            Write-Host ""
            Terraform-Init
            Terraform-Plan
            Build-And-Push-Images
            Terraform-Apply
            Update-ECS-Services
            Wait-For-Services
            Verify-Services
        }
        "plan" {
            Write-Info "Running Terraform PLAN only"
            Write-Host ""
            Terraform-Init
            Terraform-Plan
        }
        "apply" {
            Write-Info "Running Terraform APPLY only"
            Write-Host ""
            Terraform-Apply
            Update-ECS-Services
            Wait-For-Services
            Verify-Services
        }
        "build-push" {
            Write-Info "Building and pushing images only"
            Write-Host ""
            Build-And-Push-Images
            Update-ECS-Services
            Wait-For-Services
            Verify-Services
        }
        "update-services" {
            Write-Info "Updating running services"
            Write-Host ""
            Update-ECS-Services
            Wait-For-Services
            Verify-Services
        }
        "verify" {
            Write-Info "Verifying services only"
            Write-Host ""
            Verify-Services
        }
    }

    Write-Success "Deployment mode '$Mode' complete!"
    Write-Host ""
    Write-Info "Next steps:"
    Write-Host "1. Check CloudWatch logs: aws logs tail /ecs/schedule-service --follow"
    Write-Host "2. View monitoring dashboard: (check terraform-outputs.txt)"
    Write-Host "3. Configure frontend API endpoint"
    Write-Host "4. Deploy frontend to S3"
}

Main
