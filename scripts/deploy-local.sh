#!/usr/bin/env bash
# End-to-end local bring-up: compose → terraform → push images → restart fargate.
set -euo pipefail
cd "$(dirname "$0")/.."

# Load secrets from .env so Terraform can read them as TF_VAR_* variables.
if [ -f .env ]; then
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    key="${key%%$'\r'}"   # strip Windows CRLF
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
    value="${value%%$'\r'}"
    export "TF_VAR_${key,,}=${value}"  # lowercase key — Terraform var names are snake_case
  done < .env
fi

echo "==> Starting docker-compose (LocalStack)..."
docker compose up -d

echo "==> Waiting for LocalStack bootstrap to finish..."
until [ -f ./localstack-init/ids.env ]; do sleep 2; done

echo "==> Running terraform apply..."
( cd terraform && ./terraform.exe init -upgrade && ./terraform.exe apply -auto-approve -var-file=envs/local.tfvars )

echo "==> Building and pushing payment-service image to ECR..."
./scripts/push-images.sh

echo "==> Forcing Fargate redeploy with the new image..."
CLUSTER="$(cd terraform && ./terraform.exe output -raw payment_ecs_cluster)"
SERVICE="$(cd terraform && ./terraform.exe output -raw payment_ecs_service)"
API_ID="$(cd terraform && ./terraform.exe output -raw api_gateway_id)"
aws --endpoint-url=http://localhost:4566 --region us-east-1 \
  ecs update-service --cluster "$CLUSTER" --service "$SERVICE" --force-new-deployment >/dev/null || true

echo "==> Waiting for ECS task container to appear (up to 150s)..."
TASK_IP=""
for i in $(seq 1 30); do
  TASK_CONTAINER=$(docker ps --format '{{.Names}}' | grep "ls-ecs-${CLUSTER}" | head -1)
  if [ -n "$TASK_CONTAINER" ]; then
    # Grab first non-empty IP across all networks
    TASK_IP=$(docker inspect "$TASK_CONTAINER" \
      --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' \
      | tr ' ' '\n' | grep -v '^$' | head -1)
    [ -n "$TASK_IP" ] && break
  fi
  echo "  ... attempt ${i}/30"
  sleep 5
done

if [ -z "$TASK_IP" ]; then
  echo "WARNING: Could not determine ECS task IP — API Gateway integration not updated."
  echo "         Run: docker ps | grep ls-ecs-${CLUSTER}"
else
  echo "==> ECS task running at ${TASK_IP}. Patching API Gateway integration..."
  INT_ID="$(aws --endpoint-url=http://localhost:4566 --region us-east-1 \
    apigatewayv2 get-integrations --api-id "$API_ID" \
    --query 'Items[?contains(IntegrationUri, `api/payments`)].IntegrationId' \
    --output text)"
  aws --endpoint-url=http://localhost:4566 --region us-east-1 \
    apigatewayv2 update-integration \
    --api-id "$API_ID" \
    --integration-id "$INT_ID" \
    --integration-uri "http://${TASK_IP}:8000/api/payments/{proxy}" >/dev/null
  echo "==> Integration updated → http://${TASK_IP}:8000/api/payments/{proxy}"
fi

echo "==> Done. Outputs:"
( cd terraform && ./terraform.exe output )
echo ""
echo "API Gateway invoke URL: http://${API_ID}.execute-api.localhost.localstack.cloud:4566/local"
