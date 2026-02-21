#!/bin/bash

# ECS Deployment Script
# Usage: ./deploy-ecs.sh [environment]

set -e

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${1:-dev}"
ECR_REPOSITORY="my-app-ecr"
ECS_CLUSTER="${ENVIRONMENT}-title-checker-cluster"
ECS_SERVICE="${ENVIRONMENT}-title-checker-service"
CONTAINER_NAME="title-checker"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   ECS Deployment Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Environment: ${YELLOW}${ENVIRONMENT}${NC}"
echo -e "Region: ${YELLOW}${AWS_REGION}${NC}"
echo -e "Cluster: ${YELLOW}${ECS_CLUSTER}${NC}"
echo -e "Service: ${YELLOW}${ECS_SERVICE}${NC}"
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    exit 1
fi

# Check AWS credentials
echo -e "${YELLOW}Checking AWS credentials...${NC}"
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials are not configured${NC}"
    exit 1
fi
echo -e "${GREEN}✓ AWS credentials OK${NC}"

# Get AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE_TAG="$(date +%Y%m%d-%H%M%S)"

echo ""
echo -e "${YELLOW}Step 1: Login to ECR...${NC}"
aws ecr get-login-password --region ${AWS_REGION} | \
    docker login --username AWS --password-stdin ${ECR_REGISTRY}
echo -e "${GREEN}✓ Logged in to ECR${NC}"

echo ""
echo -e "${YELLOW}Step 2: Building Docker image...${NC}"
cd infra/app
docker build -t ${ECR_REPOSITORY}:${IMAGE_TAG} .
docker tag ${ECR_REPOSITORY}:${IMAGE_TAG} ${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}
docker tag ${ECR_REPOSITORY}:${IMAGE_TAG} ${ECR_REGISTRY}/${ECR_REPOSITORY}:latest
echo -e "${GREEN}✓ Docker image built${NC}"

echo ""
echo -e "${YELLOW}Step 3: Pushing image to ECR...${NC}"
docker push ${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}
docker push ${ECR_REGISTRY}/${ECR_REPOSITORY}:latest
echo -e "${GREEN}✓ Image pushed to ECR${NC}"

cd ../..

echo ""
echo -e "${YELLOW}Step 4: Updating ECS service...${NC}"
aws ecs update-service \
    --cluster ${ECS_CLUSTER} \
    --service ${ECS_SERVICE} \
    --force-new-deployment \
    --region ${AWS_REGION} \
    > /dev/null
echo -e "${GREEN}✓ ECS service update initiated${NC}"

echo ""
echo -e "${YELLOW}Step 5: Waiting for deployment to complete...${NC}"
aws ecs wait services-stable \
    --cluster ${ECS_CLUSTER} \
    --services ${ECS_SERVICE} \
    --region ${AWS_REGION}
echo -e "${GREEN}✓ Deployment completed successfully${NC}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Deployment Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Image: ${YELLOW}${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}${NC}"
echo -e "Latest: ${YELLOW}${ECR_REGISTRY}/${ECR_REPOSITORY}:latest${NC}"
echo ""

# Get ALB DNS
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --region ${AWS_REGION} \
    --query "LoadBalancers[?contains(LoadBalancerName, 'backend-alb')].DNSName" \
    --output text)

if [ -n "$ALB_DNS" ]; then
    echo -e "Service URL: ${GREEN}http://${ALB_DNS}:8501${NC}"
fi

echo ""
echo -e "${GREEN}✓ Deployment completed!${NC}"
