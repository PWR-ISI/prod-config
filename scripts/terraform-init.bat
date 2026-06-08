@echo off
REM Terraform initialization and deployment script for Windows
REM Usage: terraform-init.bat [plan|apply|destroy]

setlocal enabledelayedexpansion

set ACTION=%1

if "!ACTION!"=="" (
    set ACTION=plan
)

if not "!ACTION!"=="plan" if not "!ACTION!"=="apply" if not "!ACTION!"=="destroy" (
    echo Usage: terraform-init.bat [plan^|apply^|destroy]
    echo.
    echo Actions:
    echo   plan    - Show what will be created
    echo   apply   - Create resources
    echo   destroy - Destroy all resources
    exit /b 1
)

echo ========================================
echo Terraform !ACTION!
echo ========================================
echo.

REM Set AWS environment variables
set AWS_ENDPOINT_URL=http://localhost:4566
set AWS_ACCESS_KEY_ID=test
set AWS_SECRET_ACCESS_KEY=test
set AWS_DEFAULT_REGION=us-east-1

cd terraform

REM Clean .terraform in case of corruption
if exist .terraform (
    echo Cleaning corrupted .terraform directory...
    rmdir /s /q .terraform
)

echo Initializing Terraform...
call terraform init

if errorlevel 1 (
    echo ERROR: Terraform init failed
    pause
    cd ..
    exit /b 1
)

echo.
echo Running terraform !ACTION!...
echo.

if "!ACTION!"=="plan" (
    call terraform plan
) else if "!ACTION!"=="apply" (
    call terraform plan -out=tfplan
    echo.
    echo Review the plan above carefully!
    set /p CONFIRM="Do you want to apply these changes? (yes/no): "
    if /i "!CONFIRM!"=="yes" (
        call terraform apply tfplan
        echo.
        echo Deployment complete!
        call terraform output
    ) else (
        echo Cancelled
        del tfplan
    )
) else if "!ACTION!"=="destroy" (
    echo WARNING: This will destroy all resources!
    set /p CONFIRM="Type 'yes' to confirm destruction: "
    if /i "!CONFIRM!"=="yes" (
        call terraform destroy
    ) else (
        echo Cancelled
    )
)

echo.
cd ..
pause
