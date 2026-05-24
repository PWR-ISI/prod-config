@echo off
REM Complete ISI setup script for Windows
REM Usage: setup.bat

setlocal enabledelayedexpansion

echo.
echo ╔════════════════════════════════════════════════════════════╗
echo ║       ISI Production Config - LocalStack Setup             ║
echo ╚════════════════════════════════════════════════════════════╝
echo.

REM Check if .env exists
if not exist ".env" (
    echo Creating .env from .env.example...
    copy .env.example .env
    echo ✓ Created .env
    echo.
)

REM Menu
echo Select action:
echo.
echo 1) Start LocalStack
echo 2) Initialize Cognito
echo 3) Run Terraform Plan
echo 4) Apply Terraform
echo 5) Full Setup (all above)
echo 6) Stop LocalStack
echo 7) Clean Everything
echo.
set /p CHOICE="Enter choice (1-7): "

if "!CHOICE!"=="1" (
    call :start_localstack
) else if "!CHOICE!"=="2" (
    call :init_cognito
) else if "!CHOICE!"=="3" (
    call :terraform_plan
) else if "!CHOICE!"=="4" (
    call :terraform_apply
) else if "!CHOICE!"=="5" (
    call :full_setup
) else if "!CHOICE!"=="6" (
    call :stop_localstack
) else if "!CHOICE!"=="7" (
    call :clean_all
) else (
    echo Invalid choice
    exit /b 1
)

exit /b 0

REM ============================================================
REM Functions
REM ============================================================

:start_localstack
echo.
echo [1] Starting LocalStack...
docker-compose up -d
timeout /t 5
docker-compose logs localstack
echo ✓ LocalStack started
exit /b 0

:init_cognito
echo.
echo [2] Initializing Cognito...
call init-localstack.bat
exit /b 0

:terraform_plan
echo.
echo [3] Running Terraform Plan...
call terraform-init.bat plan
exit /b 0

:terraform_apply
echo.
echo [4] Applying Terraform...
call terraform-init.bat apply
exit /b 0

:full_setup
echo.
echo [5] Running Full Setup...
echo.
call :start_localstack
echo.
call :init_cognito
echo.
echo Update .env with Cognito IDs, then press any key to continue...
pause
echo.
call :terraform_plan
echo.
set /p APPLY="Apply Terraform? (yes/no): "
if /i "!APPLY!"=="yes" (
    call :terraform_apply
)
exit /b 0

:stop_localstack
echo.
echo [6] Stopping LocalStack...
docker-compose down
echo ✓ LocalStack stopped
exit /b 0

:clean_all
echo.
echo [7] WARNING: This will remove all data!
set /p CONFIRM="Continue? (yes/no): "
if /i not "!CONFIRM!"=="yes" (
    echo Cancelled
    exit /b 0
)
echo Cleaning...
docker-compose down -v
rmdir /s /q localstack-data 2>nul
cd terraform
del terraform.tfstate* 2>nul
rmdir /s /q .terraform 2>nul
cd ..
echo ✓ Cleaned
exit /b 0
