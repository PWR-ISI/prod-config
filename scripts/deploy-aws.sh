#!/bin/bash
set -e

echo "================================"
echo "ISI Prod-Config AWS Deployment"
echo "================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."

    if ! command -v terraform &> /dev/null; then
        echo -e "${RED}Terraform is not installed${NC}"
        exit 1
    fi

    if ! command -v aws &> /dev/null; then
        echo -e "${RED}AWS CLI is not installed${NC}"
        exit 1
    fi

    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Docker is not installed${NC}"
        exit 1
    fi

    echo -e "${GREEN}All prerequisites met${NC}"
    echo ""
}

# Get AWS account ID and region
setup_aws_info() {
    echo "Setting up AWS information..."

    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    REGION=$(aws configure get region || echo "us-east-1")

    echo -e "${GREEN}AWS Account ID: $ACCOUNT_ID${NC}"
    echo -e "${GREEN}AWS Region: $REGION${NC}"
    echo ""
}

# Build and push Docker images
build_and_push_images() {
    echo "Building and pushing Docker images..."
    echo ""

    # Login to ECR
    echo "Logging in to ECR..."
    aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

    # Schedule Service
    echo "Building schedule-service..."
    cd schedule-service
    docker build -t isi-prod-schedule:latest .

    docker tag isi-prod-schedule:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/isi-prod-schedule-repo:latest
    docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/isi-prod-schedule-repo:latest
    cd ..
    echo -e "${GREEN}Schedule service pushed${NC}"
    echo ""

    # File Upload Service
    echo "Building file-upload-service..."
    cd file-upload-service
    docker build -t isi-prod-file-upload:latest .

    docker tag isi-prod-file-upload:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/isi-prod-file-upload-repo:latest
    docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/isi-prod-file-upload-repo:latest
    cd ..
    echo -e "${GREEN}File upload service pushed${NC}"
    echo ""
}

# Initialize Terraform
terraform_init() {
    echo "Initializing Terraform..."

    cd terraform
    terraform init

    echo -e "${GREEN}Terraform initialized${NC}"
    cd ..
    echo ""
}

# Plan Terraform
terraform_plan() {
    echo "Planning Terraform changes..."

    cd terraform
    terraform plan -out=tfplan

    echo -e "${GREEN}Terraform plan complete${NC}"
    echo ""
}

# Apply Terraform
terraform_apply() {
    echo -e "${YELLOW}Ready to apply Terraform changes${NC}"
    read -p "Continue with apply? (yes/no): " response

    if [ "$response" != "yes" ]; then
        echo "Skipping Terraform apply"
        return
    fi

    cd terraform
    terraform apply tfplan

    echo -e "${GREEN}Terraform apply complete${NC}"
    echo ""

    # Save outputs
    echo "Saving outputs..."
    terraform output > terraform-outputs.txt
    echo -e "${GREEN}Outputs saved to terraform-outputs.txt${NC}"
    echo ""
}

# Update ECS services
update_ecs_services() {
    echo "Updating ECS services to pull latest images..."

    # Schedule Service
    echo "Updating schedule-service..."
    aws ecs update-service \
        --cluster isi-prod-schedule-cluster \
        --service isi-prod-schedule-svc \
        --force-new-deployment \
        --region $REGION > /dev/null
    echo -e "${GREEN}Schedule service update initiated${NC}"

    # File Upload Service
    echo "Updating file-upload-service..."
    aws ecs update-service \
        --cluster isi-prod-file-upload-cluster \
        --service isi-prod-file-upload-svc \
        --force-new-deployment \
        --region $REGION > /dev/null
    echo -e "${GREEN}File upload service update initiated${NC}"
    echo ""
}

# Wait for services to be stable
wait_for_services() {
    echo "Waiting for services to stabilize..."

    echo "Waiting for schedule-service..."
    aws ecs wait services-stable \
        --cluster isi-prod-schedule-cluster \
        --services isi-prod-schedule-svc \
        --region $REGION
    echo -e "${GREEN}Schedule service is stable${NC}"

    echo "Waiting for file-upload-service..."
    aws ecs wait services-stable \
        --cluster isi-prod-file-upload-cluster \
        --services isi-prod-file-upload-svc \
        --region $REGION
    echo -e "${GREEN}File upload service is stable${NC}"
    echo ""
}

# Verify services
verify_services() {
    echo "Verifying service deployments..."

    # Schedule Service
    echo ""
    echo "Schedule Service Status:"
    aws ecs describe-services \
        --cluster isi-prod-schedule-cluster \
        --services isi-prod-schedule-svc \
        --region $REGION \
        --query 'services[0].{Status:status,RunningCount:runningCount,DesiredCount:desiredCount,Deployments:deployments[0].{Status:status,RunningCount:runningCount,DesiredCount:desiredCount}}' \
        --output table

    # File Upload Service
    echo ""
    echo "File Upload Service Status:"
    aws ecs describe-services \
        --cluster isi-prod-file-upload-cluster \
        --services isi-prod-file-upload-svc \
        --region $REGION \
        --query 'services[0].{Status:status,RunningCount:runningCount,DesiredCount:desiredCount,Deployments:deployments[0].{Status:status,RunningCount:runningCount,DesiredCount:desiredCount}}' \
        --output table
    echo ""
}

# Main deployment flow
main() {
    check_prerequisites
    setup_aws_info

    # Ask user what to do
    echo -e "${YELLOW}Select deployment step:${NC}"
    echo "1. Full deployment (plan + apply + build + push)"
    echo "2. Build and push images only"
    echo "3. Terraform plan only"
    echo "4. Terraform apply only"
    echo "5. Update running services"
    echo ""
    read -p "Enter choice (1-5): " choice

    case $choice in
        1)
            terraform_init
            terraform_plan
            build_and_push_images
            terraform_apply
            update_ecs_services
            wait_for_services
            verify_services
            ;;
        2)
            build_and_push_images
            update_ecs_services
            wait_for_services
            verify_services
            ;;
        3)
            terraform_init
            terraform_plan
            ;;
        4)
            cd terraform
            terraform apply tfplan
            cd ..
            update_ecs_services
            wait_for_services
            verify_services
            ;;
        5)
            update_ecs_services
            wait_for_services
            verify_services
            ;;
        *)
            echo "Invalid choice"
            exit 1
            ;;
    esac

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Update frontend .env file with API Gateway endpoint"
    echo "2. Build and deploy frontend"
    echo "3. Access monitoring dashboard at:"
    echo "   $(cd terraform && terraform output -raw cloudwatch_dashboard_url 2>/dev/null || echo 'Check terraform outputs')"
}

# Run main function
main
