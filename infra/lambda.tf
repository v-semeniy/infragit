# Lambda Function for EC2 Start/Stop Scheduler

# Create ZIP archive for Lambda
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/ec2_scheduler.py"
  output_path = "${path.module}/lambda/ec2_scheduler.zip"
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_ec2_scheduler" {
  name = "${var.environment}-lambda-ec2-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.environment}-lambda-ec2-scheduler-role"
    Environment = var.environment
  }
}

# IAM Policy for Lambda - EC2 permissions
resource "aws_iam_role_policy" "lambda_ec2_policy" {
  name = "${var.environment}-lambda-ec2-policy"
  role = aws_iam_role.lambda_ec2_scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:DescribeInstanceStatus"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Attach AWS managed policy for Lambda basic execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_ec2_scheduler.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_ec2_scheduler" {
  name              = "/aws/lambda/${var.environment}-ec2-scheduler"
  retention_in_days = 7

  tags = {
    Name        = "${var.environment}-lambda-ec2-scheduler-logs"
    Environment = var.environment
  }
}

# Lambda Function - Stop EC2
resource "aws_lambda_function" "ec2_stop" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.environment}-ec2-stop"
  role             = aws_iam_role.lambda_ec2_scheduler.arn
  handler          = "ec2_scheduler.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 60

  environment {
    variables = {
      TAG_KEY   = "Name"
      TAG_VALUE = "backend-asg-instance"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_ec2_scheduler
  ]

  tags = {
    Name        = "${var.environment}-ec2-stop-lambda"
    Environment = var.environment
  }
}

# Lambda Function - Start EC2
resource "aws_lambda_function" "ec2_start" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.environment}-ec2-start"
  role             = aws_iam_role.lambda_ec2_scheduler.arn
  handler          = "ec2_scheduler.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 60

  environment {
    variables = {
      TAG_KEY   = "Name"
      TAG_VALUE = "backend-asg-instance"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_ec2_scheduler
  ]

  tags = {
    Name        = "${var.environment}-ec2-start-lambda"
    Environment = var.environment
  }
}

# EventBridge (CloudWatch Events) Rule - Stop EC2 every 5 minutes
resource "aws_cloudwatch_event_rule" "ec2_stop_schedule" {
  name                = "${var.environment}-ec2-stop-schedule"
  description         = "Trigger Lambda to stop EC2 instances every 10 minutes"
  schedule_expression = "rate(10 minutes)"

  tags = {
    Name        = "${var.environment}-ec2-stop-schedule"
    Environment = var.environment
  }
}

# EventBridge Target - Stop Lambda
resource "aws_cloudwatch_event_target" "ec2_stop_target" {
  rule      = aws_cloudwatch_event_rule.ec2_stop_schedule.name
  target_id = "StopEC2Lambda"
  arn       = aws_lambda_function.ec2_stop.arn

  input = jsonencode({
    action = "stop"
  })
}

# Lambda Permission for EventBridge - Stop
resource "aws_lambda_permission" "allow_eventbridge_stop" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_stop.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ec2_stop_schedule.arn
}

# EventBridge Rule - Start EC2 (offset by 5 minutes)
# Note: Using cron to create 5-minute offset
resource "aws_cloudwatch_event_rule" "ec2_start_schedule" {
  name                = "${var.environment}-ec2-start-schedule"
  description         = "Trigger Lambda to start EC2 instances (5 min after stop)"
  schedule_expression = "rate(10 minutes)"

  tags = {
    Name        = "${var.environment}-ec2-start-schedule"
    Environment = var.environment
  }
}

# EventBridge Target - Start Lambda
resource "aws_cloudwatch_event_target" "ec2_start_target" {
  rule      = aws_cloudwatch_event_rule.ec2_start_schedule.name
  target_id = "StartEC2Lambda"
  arn       = aws_lambda_function.ec2_start.arn

  input = jsonencode({
    action = "start"
  })
}

# Lambda Permission for EventBridge - Start
resource "aws_lambda_permission" "allow_eventbridge_start" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_start.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ec2_start_schedule.arn
}

# Step Functions State Machine for Start/Stop workflow (Alternative approach)
# This creates a proper 5-minute delay between stop and start

resource "aws_sfn_state_machine" "ec2_scheduler" {
  name     = "${var.environment}-ec2-scheduler-workflow"
  role_arn = aws_iam_role.step_functions_role.arn

  definition = jsonencode({
    Comment = "EC2 Start/Stop workflow with 2-minute delay"
    StartAt = "StopEC2"
    States = {
      StopEC2 = {
        Type     = "Task"
        Resource = aws_lambda_function.ec2_stop.arn
        Next     = "Wait2Minutes"
      }
      Wait2Minutes = {
        Type    = "Wait"
        Seconds = 120  # 2 minutes
        Next    = "StartEC2"
      }
      StartEC2 = {
        Type     = "Task"
        Resource = aws_lambda_function.ec2_start.arn
        End      = true
      }
    }
  })

  tags = {
    Name        = "${var.environment}-ec2-scheduler-workflow"
    Environment = var.environment
  }
}

# IAM Role for Step Functions
resource "aws_iam_role" "step_functions_role" {
  name = "${var.environment}-step-functions-ec2-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.environment}-step-functions-role"
    Environment = var.environment
  }
}

# IAM Policy for Step Functions to invoke Lambda
resource "aws_iam_role_policy" "step_functions_policy" {
  name = "${var.environment}-step-functions-lambda-policy"
  role = aws_iam_role.step_functions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.ec2_stop.arn,
          aws_lambda_function.ec2_start.arn
        ]
      }
    ]
  })
}

# EventBridge Rule to trigger Step Functions every 10 minutes
resource "aws_cloudwatch_event_rule" "trigger_step_functions" {
  name                = "${var.environment}-trigger-ec2-scheduler-workflow"
  description         = "Trigger Step Functions workflow every 10 minutes"
  schedule_expression = "rate(10 minutes)"

  tags = {
    Name        = "${var.environment}-trigger-workflow"
    Environment = var.environment
  }
}

# EventBridge Target for Step Functions
resource "aws_cloudwatch_event_target" "step_functions_target" {
  rule     = aws_cloudwatch_event_rule.trigger_step_functions.name
  arn      = aws_sfn_state_machine.ec2_scheduler.arn
  role_arn = aws_iam_role.eventbridge_step_functions.arn
}

# IAM Role for EventBridge to trigger Step Functions
resource "aws_iam_role" "eventbridge_step_functions" {
  name = "${var.environment}-eventbridge-step-functions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "eventbridge_step_functions_policy" {
  name = "${var.environment}-eventbridge-sf-policy"
  role = aws_iam_role.eventbridge_step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = aws_sfn_state_machine.ec2_scheduler.arn
      }
    ]
  })
}
