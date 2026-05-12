#!/usr/bin/env bash
# Builds microservice images and pushes them into the LocalStack ECR so ECS/Fargate task definitions can pull.
# Requires: docker, awslocal (or aws CLI with --endpoint-url), terraform applied (so repos exist).
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
ENDPOINT="${AWS_ENDPOINT_URL:-http://localhost:4566}"
ACCOUNT_ID="000000000000"

aws_local() {
  aws --endpoint-url="$ENDPOINT" --region "$REGION" "$@"
}

# service-context-path → ECR repo name (must match terraform).
declare -A SERVICES=(
  [payment-service]="prod-config-payment-repo"
)

for ctx in "${!SERVICES[@]}"; do
  repo="${SERVICES[$ctx]}"
  echo "==> $ctx → $repo"

  aws_local ecr describe-repositories --repository-names "$repo" >/dev/null 2>&1 \
    || aws_local ecr create-repository --repository-name "$repo" >/dev/null

  registry="${ACCOUNT_ID}.dkr.ecr.${REGION}.localhost.localstack.cloud:4566"
  image="${registry}/${repo}:latest"

  docker build -t "$image" "./${ctx}"
  docker push "$image"
done

echo "Done. Images pushed to LocalStack ECR."
