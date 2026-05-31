@echo off
REM ISI Medical System - LocalStack Fargate Deployment
REM Windows Batch Script

setlocal enabledelayedexpansion

set ACTION=%1
if "!ACTION!"=="" set ACTION=full

REM Colors (using echo with special chars won't work in batch, using simple output)
echo.
echo ====================================================
echo ISI Medical System - LocalStack Deployment
echo ====================================================
echo.

REM Set AWS endpoint variables
set AWS_ENDPOINT_URL=http://localhost:4566
set AWS_ACCESS_KEY_ID=test
set AWS_SECRET_ACCESS_KEY=test
set AWS_DEFAULT_REGION=us-east-1

if "!ACTION!"=="full" goto FULL_DEPLOY
if "!ACTION!"=="build" goto BUILD_IMAGES
if "!ACTION!"=="push" goto PUSH_ECR
if "!ACTION!"=="deploy" goto TERRAFORM_DEPLOY
if "!ACTION!"=="clean" goto CLEAN
if "!ACTION!"=="status" goto CHECK_STATUS

echo Invalid action. Use: full, build, push, deploy, clean, status
exit /b 1

:FULL_DEPLOY
echo [*] Starting FULL deployment...
echo.

call :START_LOCALSTACK
call :BUILD_IMAGES
call :PUSH_ECR
call :TERRAFORM_DEPLOY
call :FRONTEND_BUILD

echo.
echo ====================================================
echo [OK] Deployment Complete!
echo ====================================================
echo.
echo Access at:
echo   Frontend: http://localhost:3000
echo   Swagger: http://localhost:8001/api/docs/
echo.
echo Check terraform outputs:
echo   cd terraform
echo   terraform output
echo.
exit /b 0

:START_LOCALSTACK
echo [1/5] Starting LocalStack...

REM Check if already running
docker ps | findstr "prod-localstack" >nul
if !errorlevel! equ 0 (
    echo [WARN] LocalStack already running
    goto :EOF
)

echo [*] Starting container...
docker-compose up -d

echo [*] Waiting for LocalStack to be healthy...
set RETRIES=0
:WAIT_HEALTHY
docker ps --filter "name=prod-localstack" --filter "health=healthy" -q >nul
if !errorlevel! equ 0 (
    echo [OK] LocalStack is healthy
    goto :EOF
)

set /a RETRIES+=1
if !RETRIES! gtr 30 (
    echo [ERROR] LocalStack failed to start
    exit /b 1
)

timeout /t 2 /nobreak
goto WAIT_HEALTHY

:BUILD_IMAGES
echo.
echo [2/5] Building Docker images...

set SERVICES=auth-identity-service appointment-service schedule-service payment-service notification-service facility-staff-service medical-record-service audit-logging-service frontend-portal

for %%S in (%SERVICES%) do (
    echo [*] Building %%S...
    docker build -t localhost:4566/isi-%%S:latest %%S
    if !errorlevel! neq 0 (
        echo [ERROR] Failed to build %%S
        exit /b 1
    )
)

echo [OK] All services built
goto :EOF

:PUSH_ECR
echo.
echo [3/5] Pushing to LocalStack ECR...

set SERVICES=auth-identity-service appointment-service schedule-service payment-service notification-service facility-staff-service medical-record-service audit-logging-service frontend-portal

for %%S in (%SERVICES%) do (
    echo [*] Creating ECR repo isi-%%S...
    aws ecr create-repository --repository-name isi-%%S --endpoint-url !AWS_ENDPOINT_URL! 2>nul

    echo [*] Pushing isi-%%S...
    docker push localhost:4566/isi-%%S:latest
    if !errorlevel! neq 0 (
        echo [ERROR] Failed to push %%S
        exit /b 1
    )
)

echo [OK] All services pushed to ECR
goto :EOF

:TERRAFORM_DEPLOY
echo.
echo [4/5] Deploying with Terraform...

cd terraform

echo [*] Initializing terraform...
call terraform init

echo [*] Planning...
call terraform plan -out=tfplan

echo [*] Applying...
call terraform apply tfplan

echo [*] Getting outputs...
call terraform output

cd ..

echo [OK] Terraform deployment complete
goto :EOF

:FRONTEND_BUILD
echo.
echo [5/5] Building and uploading frontend...

cd frontend-portal
echo [*] Installing dependencies...
call npm install

echo [*] Building...
call npm run build

echo [*] Uploading to S3...
aws s3 sync dist/ s3://prod-config-frontend/ --endpoint-url http://localhost:4566 --delete --region us-east-1
if !errorlevel! neq 0 (
    echo [WARN] Frontend upload may have issues but continuing
)

cd ..

echo [OK] Frontend built and uploaded
goto :EOF

:CHECK_STATUS
echo [*] Checking deployment status...
echo.

echo LocalStack:
docker ps --filter "name=prod-localstack"

echo.
echo ECR Repositories:
aws ecr list-repositories --endpoint-url !AWS_ENDPOINT_URL! --query 'repositories[].repositoryName' --output table

echo.
echo ECS Services:
aws ecs list-services --cluster isi-prod-cluster --endpoint-url !AWS_ENDPOINT_URL! --query 'serviceArns' --output table

echo.
echo ECS Tasks:
aws ecs list-tasks --cluster isi-prod-cluster --endpoint-url !AWS_ENDPOINT_URL! --query 'taskArns' --output table

goto :EOF

:CLEAN
echo [*] Cleaning deployment...
echo.

echo [*] Destroying Terraform...
cd terraform
call terraform destroy -auto-approve
cd ..

echo [*] Stopping LocalStack...
docker-compose down -v

echo [OK] Cleanup complete
goto :EOF

endlocal
exit /b 0
