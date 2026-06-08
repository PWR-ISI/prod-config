@echo off
setlocal enabledelayedexpansion

set AWS_ENDPOINT_URL=http://localhost:4566
set AWS_ACCESS_KEY_ID=test
set AWS_SECRET_ACCESS_KEY=test
set AWS_DEFAULT_REGION=us-east-1

echo.
echo ===============================================
echo ISI Deployment Fix
echo ===============================================
echo.

echo [1] Starting Frontend Development Server...
cd frontend-portal

REM Check if node_modules exists
if not exist "node_modules" (
    echo [*] Installing dependencies...
    call npm install
)

echo [*] Starting dev server on port 3000...
start cmd /k "npm run dev"

timeout /t 5

cd ..

echo.
echo [2] Checking Terraform Outputs...
cd terraform

if exist "terraform.tfstate" (
    echo [*] Terraform state found, showing outputs:
    call terraform output
) else (
    echo [ERROR] Terraform state not found!
    echo [*] Running terraform apply...
    call terraform plan -out=tfplan
    call terraform apply tfplan
    call terraform output
)

cd ..

echo.
echo [3] Verifying Services...
echo.

echo Checking API Gateway...
for /f "tokens=*" %%A in ('aws apigatewayv2 get-apis --endpoint-url !AWS_ENDPOINT_URL! --query "Items[0].ApiId" --output text') do set API_ID=%%A

if "!API_ID!"=="" (
    echo [ERROR] API Gateway not found!
    echo [*] Check terraform apply logs above
) else (
    echo [OK] API Gateway ID: !API_ID!
    echo.
    echo API Gateway Routes:
    aws apigatewayv2 get-routes --api-id !API_ID! --endpoint-url !AWS_ENDPOINT_URL! --query "Items[].{Path:RouteKey,Target:Target}" --output table
)

echo.
echo [4] Testing Auth API...
echo.

REM Get the API invoke URL
for /f "tokens=*" %%A in ('aws apigatewayv2 get-apis --endpoint-url !AWS_ENDPOINT_URL! --query "Items[0].ApiEndpoint" --output text') do set API_ENDPOINT=%%A

if not "!API_ENDPOINT!"=="" (
    echo Testing: !API_ENDPOINT!/auth/login
    echo.
    curl -X POST "!API_ENDPOINT!/auth/login" ^
        -H "Content-Type: application/json" ^
        -d "{\"email\":\"admin@example.com\",\"password\":\"admin123\"}" ^
        -s | jq .
) else (
    echo [ERROR] Cannot determine API endpoint
)

echo.
echo ===============================================
echo Frontend should be running on: http://localhost:3000
echo ===============================================
echo.

pause
