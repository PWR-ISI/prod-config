@echo off
REM LocalStack initialization script for Windows
REM Usage: init-localstack.bat

setlocal enabledelayedexpansion

echo ========================================
echo ISI LocalStack Initialization
echo ========================================

REM Set AWS environment variables for LocalStack
set AWS_ENDPOINT_URL=http://localhost:4566
set AWS_ACCESS_KEY_ID=test
set AWS_SECRET_ACCESS_KEY=test
set AWS_DEFAULT_REGION=us-east-1

echo.
echo 1. Waiting for LocalStack to be ready...
timeout /t 10

REM Check if LocalStack is healthy
echo Checking LocalStack health...
curl -s http://localhost:4566/_localstack/health >nul
if errorlevel 1 (
    echo ERROR: LocalStack is not responding!
    echo Make sure docker-compose up -d was run successfully
    pause
    exit /b 1
)
echo ✓ LocalStack is ready!

echo.
echo 2. Creating Cognito User Pool...
for /f "tokens=*" %%i in ('aws cognito-idp create-user-pool --pool-name isi-user-pool --region us-east-1 --endpoint-url %AWS_ENDPOINT_URL% --query "UserPool.Id" --output text 2^>nul') do set POOL_ID=%%i

if "!POOL_ID!"=="" (
    echo ERROR: Failed to create User Pool
    pause
    exit /b 1
)
echo ✓ Created User Pool: !POOL_ID!

echo.
echo 3. Creating Cognito App Client...
for /f "tokens=*" %%i in ('aws cognito-idp create-user-pool-client --user-pool-id !POOL_ID! --client-name isi-app --region us-east-1 --endpoint-url %AWS_ENDPOINT_URL% --query "UserPoolClient.ClientId" --output text 2^>nul') do set CLIENT_ID=%%i

if "!CLIENT_ID!"=="" (
    echo ERROR: Failed to create App Client
    pause
    exit /b 1
)
echo ✓ Created App Client: !CLIENT_ID!

echo.
echo ========================================
echo Credentials Created Successfully!
echo ========================================
echo.
echo Update your .env file with these values:
echo.
echo COGNITO_USER_POOL_ID=!POOL_ID!
echo COGNITO_APP_CLIENT_ID=!CLIENT_ID!
echo.
echo ========================================
echo.
pause
