@echo off
setlocal enabledelayedexpansion

set ACCOUNT_ID=205096517704
set REGION=us-east-1

echo Logging in to ECR...
for /f %%i in ('aws ecr get-login-password --region %REGION%') do set PASS=%%i
echo %PASS% | docker login --username AWS --password-stdin %ACCOUNT_ID%.dkr.ecr.%REGION%.amazonaws.com

echo.
echo Building and pushing services...
echo.

setlocal enabledelayedexpansion
set services[0]=auth-identity-service,isi-prod-auth
set services[1]=appointment-service,isi-prod-core
set services[2]=schedule-service,isi-prod-schedule
set services[3]=payment-service,isi-prod-payment
set services[4]=notification-service,isi-prod-notification
set services[5]=facility-staff-service,isi-prod-facility
set services[6]=medical-record-service,isi-prod-medical
set services[7]=audit-logging-service,isi-prod-audit

for /l %%i in (0,1,7) do (
    for /f "tokens=1,2 delims=," %%a in ("!services[%%i]!") do (
        set SERVICE=%%a
        set REPO=%%b-repo
        set IMAGE=%ACCOUNT_ID%.dkr.ecr.%REGION%.amazonaws.com/!REPO!:latest

        echo Building !SERVICE!...
        docker build -t !IMAGE! !SERVICE! >nul 2>&1
        if !errorlevel! equ 0 (
            echo   Pushing...
            docker push !IMAGE! >nul 2>&1
            if !errorlevel! equ 0 (
                echo   [OK]
            ) else (
                echo   [PUSH FAILED]
            )
        ) else (
            echo   [BUILD FAILED]
        )
    )
)

echo.
echo Done
