data "aws_autoscaling_group" "backend" {
  name = aws_autoscaling_group.backend.name
}

data "aws_instances" "asg_instances" {
  instance_tags = {
    "Name" = "backend-asg-instance"
  }
  filter {
    name   = "instance.group-id"
    values = [data.aws_autoscaling_group.backend.id]
  }
}

resource "aws_ssm_document" "run_docker" {
  name          = "RunTitleCheckerDocker"
  document_type = "Command"
  document_format = "JSON"
  
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Deploy Docker container from ECR to EC2"
    parameters = {
      imagetag = {
        type        = "String"
        description = "Docker image tag to deploy"
        default     = "latest"
      }
    }
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "deployDocker"
        inputs = {
          runCommand = [
            "#!/bin/bash",
            "set -e",
            "",
            "# Update system packages",
            "yum update -y 2>&1 || apt-get update -y 2>&1",
            "",
            "# Install Docker if not present",
            "if ! command -v docker &> /dev/null; then",
            "  echo 'Installing Docker...'",
            "  curl -fsSL https://get.docker.com | sh",
            "  systemctl enable docker",
            "fi",
            "",
            "# Start Docker service",
            "systemctl start docker",
            "systemctl status docker",
            "",
            "# Get AWS account ID",
            "AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)",
            "AWS_REGION=us-east-1",
            "ECR_REGISTRY=$${AWS_ACCOUNT_ID}.dkr.ecr.$${AWS_REGION}.amazonaws.com",
            "",
            "# Login to ECR",
            "echo 'Logging into ECR...'",
            "aws ecr get-login-password --region $${AWS_REGION} | docker login --username AWS --password-stdin $${ECR_REGISTRY}",
            "",
            "# Pull Docker image",
            "IMAGE_TAG={{ imagetag }}",
            "echo \"Pulling image: $${ECR_REGISTRY}/title_checker:$${IMAGE_TAG}\"",
            "docker pull $${ECR_REGISTRY}/title_checker:$${IMAGE_TAG}",
            "",
            "# Stop and remove existing container",
            "echo 'Stopping existing container...'",
            "docker stop title_checker 2>/dev/null || true",
            "docker rm title_checker 2>/dev/null || true",
            "",
            "# Run new container",
            "echo 'Starting new container...'",
            "docker run -d \\",
            "  --name title_checker \\",
            "  --restart unless-stopped \\",
            "  -p 8501:8501 \\",
            "  $${ECR_REGISTRY}/title_checker:$${IMAGE_TAG}",
            "",
            "# Verify container is running",
            "sleep 5",
            "docker ps | grep title_checker",
            "echo 'Container deployed successfully!'"
          ]
        }
      }
    ]
  })
  
  tags = {
    Name = "RunTitleCheckerDocker"
  }
}

resource "aws_ssm_association" "run_docker" {
  name = aws_ssm_document.run_docker.name

  targets {
    key    = "tag:Name"
    values = ["backend-asg-instance"] # Тег ваших EC2 інстансів
  }

  parameters = {
    imagetag = "latest" # Передайте значення як рядок
  }
}