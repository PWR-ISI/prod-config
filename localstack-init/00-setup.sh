#!/usr/bin/env bash
# Provisions Cognito User Pool, SQS queues, and API Gateway on LocalStack startup.
# Runs automatically via /etc/localstack/init/ready.d/ on LocalStack boot.
set -euo pipefail

REGION="us-east-1"
ACCOUNT_ID="000000000000"

echo "=== [1/3] Provisioning Cognito ==="

POOL_ID=$(awslocal cognito-idp create-user-pool \
  --pool-name medical-user-pool \
  --schema '[
    {"Name":"custom:role","AttributeDataType":"String","Mutable":true,"Required":false}
  ]' \
  --policies '{"PasswordPolicy":{"MinimumLength":8,"RequireUppercase":false,"RequireLowercase":false,"RequireNumbers":false,"RequireSymbols":false}}' \
  --auto-verified-attributes email \
  --query 'UserPool.Id' \
  --output text)

echo "  User Pool ID: $POOL_ID"

CLIENT_ID=$(awslocal cognito-idp create-user-pool-client \
  --user-pool-id "$POOL_ID" \
  --client-name medical-app-client \
  --no-generate-secret \
  --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_REFRESH_TOKEN_AUTH ALLOW_USER_SRP_AUTH \
  --query 'UserPoolClient.ClientId' \
  --output text)

echo "  App Client ID: $CLIENT_ID"

# Persist IDs to Secrets Manager so services can fetch them at runtime
awslocal secretsmanager create-secret \
  --name "/medical/cognito/user-pool-id" \
  --secret-string "$POOL_ID"

awslocal secretsmanager create-secret \
  --name "/medical/cognito/app-client-id" \
  --secret-string "$CLIENT_ID"

echo "=== [2/3] Provisioning SQS Queues ==="

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
    --attributes "MessageRetentionPeriod=86400,VisibilityTimeout=30"
  echo "  Created: $QUEUE"
done

echo "=== [3/3] Provisioning API Gateway (HTTP API v2) ==="

API_ID=$(awslocal apigatewayv2 create-api \
  --name "medical-api" \
  --protocol-type HTTP \
  --query 'ApiId' \
  --output text)

echo "  API ID: $API_ID"

# JWT authorizer backed by LocalStack Cognito
# In LocalStack, the issuer URL uses the localstack endpoint
AUTH_ID=$(awslocal apigatewayv2 create-authorizer \
  --api-id "$API_ID" \
  --authorizer-type JWT \
  --identity-source '$request.header.Authorization' \
  --name cognito-jwt \
  --jwt-configuration "Audience=${CLIENT_ID},Issuer=http://localhost:4566/${POOL_ID}" \
  --query 'AuthorizerId' \
  --output text)

echo "  Authorizer ID: $AUTH_ID"

# Helper: create integration + route for one service path prefix
create_route() {
  local path_prefix="$1"
  local backend_host="$2"

  INTEGRATION_ID=$(awslocal apigatewayv2 create-integration \
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
    --target "integrations/${INTEGRATION_ID}" \
    --authorization-type JWT \
    --authorizer-id "$AUTH_ID"

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

# Health check route — no auth required
HEALTH_INTEGRATION_ID=$(awslocal apigatewayv2 create-integration \
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
  --target "integrations/${HEALTH_INTEGRATION_ID}" \
  --authorization-type NONE

# Auto-deploy stage
awslocal apigatewayv2 create-stage \
  --api-id "$API_ID" \
  --stage-name '$default' \
  --auto-deploy

echo ""
echo "=== Setup Complete ==="
echo "API Gateway URL : http://localhost:4566/_aws/execute-api/${API_ID}/\$default"
echo "Cognito Pool ID : $POOL_ID"
echo "Cognito Client  : $CLIENT_ID"
echo ""
echo "Set these in your .env.local for service-level overrides:"
echo "  COGNITO_USER_POOL_ID=${POOL_ID}"
echo "  COGNITO_APP_CLIENT_ID=${CLIENT_ID}"
