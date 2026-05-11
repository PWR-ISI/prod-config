#!/usr/bin/env bash
# End-to-end local bring-up: compose → terraform → push images → restart fargate.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Starting docker-compose (LocalStack + microservices + postgres)..."
docker compose up -d --build

echo "==> Waiting for LocalStack bootstrap to finish..."
until [ -f ./localstack-init/ids.env ]; do sleep 2; done

echo "==> Running terraform apply..."
( cd terraform && terraform init -upgrade && terraform apply -auto-approve -var-file=envs/local.tfvars )

echo "==> Building and pushing images to ECR..."
./scripts/push-images.sh

echo "==> Forcing Fargate redeploy with the new images..."
CLUSTER="$(cd terraform && terraform output -raw ecs_cluster 2>/dev/null || echo prod-config-core-cluster)"
SERVICE="$(cd terraform && terraform output -raw ecs_service 2>/dev/null || echo prod-config-core-svc)"
aws --endpoint-url=http://localhost:4566 --region us-east-1 \
  ecs update-service --cluster "$CLUSTER" --service "$SERVICE" --force-new-deployment >/dev/null || true

echo "==> Done. Outputs:"
( cd terraform && terraform output )
