@echo off
setlocal enabledelayedexpansion

set AWS_ENDPOINT_URL=http://localhost:4566
set AWS_ACCESS_KEY_ID=test
set AWS_SECRET_ACCESS_KEY=test
set AWS_DEFAULT_REGION=us-east-1

echo.
echo ===============================================
echo ISI System Diagnostic
echo ===============================================
echo.

echo [1] LocalStack Status
docker ps --filter "name=prod-localstack"
echo.

echo [2] ECR Repositories
aws ecr list-repositories --endpoint-url !AWS_ENDPOINT_URL! --query "repositories[].repositoryName" --output table
echo.

echo [3] ECS Cluster & Services
aws ecs describe-clusters --clusters isi-prod-cluster --endpoint-url !AWS_ENDPOINT_URL! --query "clusters[0].{name:clusterName,status:status}"
echo.

echo [4] Running Tasks
aws ecs list-tasks --cluster isi-prod-cluster --endpoint-url !AWS_ENDPOINT_URL! --query "taskArns" --output table
echo.

echo [5] API Gateway
echo Checking API Gateway routes...
aws apigatewayv2 get-apis --endpoint-url !AWS_ENDPOINT_URL! --query "Items[0].{ApiId:ApiId,Name:Name,Status:ProtocolType}" --output table
echo.

echo [6] S3 Buckets
aws s3 ls --endpoint-url !AWS_ENDPOINT_URL!
echo.

echo [7] S3 Frontend Contents
aws s3 ls s3://isi-prod-frontend/ --endpoint-url !AWS_ENDPOINT_URL!
echo.

echo [8] Terraform State
cd terraform
terraform show -json | findstr /i "resource"
cd ..
echo.

echo [9] Logs from Auth Service
echo Checking if auth service logs exist...
aws logs describe-log-groups --endpoint-url !AWS_ENDPOINT_URL! --query "logGroups[].logGroupName" --output table
echo.

echo ===============================================
echo Diagnostic Complete
echo ===============================================
echo.

pause
