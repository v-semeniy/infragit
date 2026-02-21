locals {
  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e
    exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
    
    echo "Starting user-data script..."
    
    # Update system
    yum update -y
    
    # Install Docker
    amazon-linux-extras install docker -y
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ec2-user
    
    # Install SSM agent
    yum install -y amazon-ssm-agent
    systemctl start amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    
    # Get AWS account ID and region
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=us-east-1
    ECR_REGISTRY=$${AWS_ACCOUNT_ID}.dkr.ecr.$${AWS_REGION}.amazonaws.com
    
    # Login to ECR
    echo "Logging into ECR..."
    aws ecr get-login-password --region $${AWS_REGION} | docker login --username AWS --password-stdin $${ECR_REGISTRY}
    
    # Pull and run Docker container from ECR
    echo "Pulling Docker image from ECR..."
    docker pull $${ECR_REGISTRY}/my-app-ecr:latest || echo "Image not found, will wait for CI/CD to push it"
    
    # If image exists, run it
    if docker images | grep -q my-app-ecr; then
      echo "Starting container..."
      docker run -d \
        --name title_checker \
        --restart unless-stopped \
        -p 8501:8501 \
        $${ECR_REGISTRY}/my-app-ecr:latest
      
      echo "Container started successfully!"
      docker ps
    else
      echo "No image found in ECR. Please push image via CI/CD pipeline."
    fi
    
    echo "User-data script completed!"
  EOF
  )
}

# Data source for latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Launch template for Auto Scaling Group
resource "aws_launch_template" "backend" {
  name_prefix   = "backend-template"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  key_name      = var.key_pair_name 

  vpc_security_group_ids = [aws_security_group.ec2.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  user_data = local.user_data

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name          = "backend-instance"
      Type          = "backend"
      AutoStartStop = "true"  # Tag for Lambda scheduler
      Environment   = var.environment
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "backend" {
  name                = "backend-asg"
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns   = [aws_lb_target_group.backend.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300

  min_size         = 1
  max_size         = 1
  desired_capacity = 1

  launch_template {
    id      = aws_launch_template.backend.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "backend-asg-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "production"
    propagate_at_launch = true
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }
}
