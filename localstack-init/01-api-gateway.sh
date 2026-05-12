#!/usr/bin/env bash
# Sets up per-service SQS consuming queues and the HTTP API Gateway v2.
# Runs after 00-bootstrap.sh (which handles Cognito, event queues, and the test user).
set -euo pipefail

IDS_FILE="/etc/localstack/init/ready.d/ids.env"

# Wait for 00-bootstrap.sh to write IDs
for i in $(seq 1 30); do
  [ -f "$IDS_FILE" ] && break
  echo "[api-gateway] waiting for ids.env ($i/30)..."
  sleep 1
done

if [ ! -f "$IDS_FILE" ]; then
  echo "[api-gateway] ERROR: ids.env not found — did 00-bootstrap.sh fail?"
  exit 1
fi

# shellcheck source=/dev/null
source "$IDS_FILE"

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
ACCOUNT_ID="000000000000"
CLIENT_ID="$COGNITO_USER_POOL_CLIENT_ID"
POOL_ID="$COGNITO_USER_POOL_ID"

echo "=== [1/2] Per-service SQS consuming queues ==="
QUEUES=(
  "auth-identity-service-queue"
  "appointment-service-queue"
  "schedule-service-queue"
  "payment-service-queue"
  "notification-service-queue"
  "facility-staff-service-queue"
  "medical-record-service-queue"
  "audit-service-queue"
)

for QUEUE in "${QUEUES[@]}"; do
  awslocal sqs create-queue \
    --queue-name "$QUEUE" \
    --attributes "MessageRetentionPeriod=86400,VisibilityTimeout=30" \
    >/dev/null
  echo "  Created: $QUEUE"
done

echo "=== [2/2] HTTP API Gateway v2 ==="

API_ID=$(awslocal apigatewayv2 create-api \
  --name "medical-api" \
  --protocol-type HTTP \
  --query 'ApiId' \
  --output text)

echo "  API ID: $API_ID"

AUTH_ID=$(awslocal apigatewayv2 create-authorizer \
  --api-id "$API_ID" \
  --authorizer-type JWT \
  --identity-source '$request.header.Authorization' \
  --name cognito-jwt \
  --jwt-configuration "Audience=${CLIENT_ID},Issuer=http://localhost:4566/${POOL_ID}" \
  --query 'AuthorizerId' \
  --output text)

echo "  Authorizer ID: $AUTH_ID"

create_route() {
  local path_prefix="$1"
  local backend_host="$2"

  INT_ID=$(awslocal apigatewayv2 create-integration \
    --api-id "$API_ID" \
    --integration-type HTTP_PROXY \
    --integration-method ANY \
    --integration-uri "http://${backend_host}/api/v1/{proxy}" \
    --payload-format-version "1.0" \
    --query 'IntegrationId' \
    --output text)

  awslocal apigatewayv2 create-route \
    --api-id "$API_ID" \
    --route-key "ANY /${path_prefix}/{proxy+}" \
    --target "integrations/${INT_ID}" \
    --authorization-type JWT \
    --authorizer-id "$AUTH_ID" \
    >/dev/null

  echo "  Route: ANY /${path_prefix}/{proxy+} -> http://${backend_host}/api/v1/{proxy}"
}

create_route "auth"          "auth-identity-service:8000"
create_route "appointments"  "appointment-service:8000"
create_route "schedule"      "schedule-service:8000"
create_route "payments"      "payment-service:8000"
create_route "notifications" "notification-service:8000"
create_route "facilities"    "facility-staff-service:8000"
create_route "records"       "medical-record-service:8000"
create_route "audit"         "audit-logging-service:8000"

# Health check — no auth
HEALTH_INT_ID=$(awslocal apigatewayv2 create-integration \
  --api-id "$API_ID" \
  --integration-type HTTP_PROXY \
  --integration-method GET \
  --integration-uri "http://auth-identity-service:8000/health/" \
  --payload-format-version "1.0" \
  --query 'IntegrationId' \
  --output text)

awslocal apigatewayv2 create-route \
  --api-id "$API_ID" \
  --route-key "GET /health" \
  --target "integrations/${HEALTH_INT_ID}" \
  --authorization-type NONE \
  >/dev/null

awslocal apigatewayv2 create-stage \
  --api-id "$API_ID" \
  --stage-name '$default' \
  --auto-deploy \
  >/dev/null

# Append API Gateway ID to ids.env so services/tooling can reference it
echo "API_GATEWAY_ID=$API_ID" >> "$IDS_FILE"

echo ""
echo "=== Done ==="
echo "  API Gateway : http://localhost:4566/_aws/execute-api/${API_ID}/\$default"
echo "  Test login  : POST /auth/login  user=test@example.com  pass=Test1234"
