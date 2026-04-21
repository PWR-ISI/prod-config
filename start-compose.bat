@echo off
:: Usage: start-compose.bat all|api-gateway|appointment|audit-logging|auth-identity|facility-staff|medical-record|notification|payment|schedule|frontend
:: Runs docker compose for the requested service(s)

SET SERVICE=%1
if "%SERVICE%"=="" set SERVICE=all

if "%SERVICE%"=="all" (
  docker compose -f api-gateway/docker-compose.yml -f appointment-service/docker-compose.yml -f audit-logging-service/docker-compose.yml -f auth-identity-service/docker-compose.yml -f facility-staff-service/docker-compose.yml -f medical-record-service/docker-compose.yml -f notification-service/docker-compose.yml -f payment-service/docker-compose.yml -f schedule-service/docker-compose.yml -f frontend-portal/docker-compose.yml up -d --build
  goto :eof
)

if "%SERVICE%"=="api-gateway" (
  docker compose -f api-gateway/docker-compose.yml up -d --build
  goto :eof
)
if "%SERVICE%"=="appointment" (
  docker compose -f appointment-service/docker-compose.yml up -d --build
  goto :eof
)
if "%SERVICE%"=="audit-logging" (
  docker compose -f audit-logging-service/docker-compose.yml up -d --build
  goto :eof
)
if "%SERVICE%"=="auth-identity" (
  docker compose -f auth-identity-service/docker-compose.yml up -d --build
  goto :eof
)
if "%SERVICE%"=="facility-staff" (
  docker compose -f facility-staff-service/docker-compose.yml up -d --build
  goto :eof
)
if "%SERVICE%"=="medical-record" (
  docker compose -f medical-record-service/docker-compose.yml up -d --build
  goto :eof
)
if "%SERVICE%"=="notification" (
  docker compose -f notification-service/docker-compose.yml up -d --build
  goto :eof
)
if "%SERVICE%"=="payment" (
  docker compose -f payment-service/docker-compose.yml up -d --build
  goto :eof
)
if "%SERVICE%"=="schedule" (
  docker compose -f schedule-service/docker-compose.yml up -d --build
  goto :eof
)
if "%SERVICE%"=="frontend" (
  docker compose -f frontend-portal/docker-compose.yml up -d --build
  goto :eof
)

echo Unknown service '%SERVICE%'
exit /b 1