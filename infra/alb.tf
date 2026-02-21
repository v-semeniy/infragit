# Application Load Balancer
resource "aws_lb" "backend" {
  name               = "backend-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false

  tags = {
    Name = "backend-alb"
  }
}

# Target Group for the Load Balancer
resource "aws_lb_target_group" "backend" {
  name     = "backend-tg"
  port     = 8501              
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  
  # Deregistration delay
  deregistration_delay = 30
  
  # Target type
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 10
    matcher             = "200,301,302"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
  }
  
  # Stickiness (session affinity)
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = false
  }

  tags = {
    Name = "backend-target-group"
  }
}

# Load Balancer Listener
resource "aws_lb_listener" "backend" {
  load_balancer_arn = aws_lb.backend.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    
    forward {
      target_group {
        arn = aws_lb_target_group.backend.arn
      }
    }
  }
}
