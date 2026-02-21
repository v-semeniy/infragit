# 🕐 EC2 Scheduler Lambda

## Що це робить?

AWS Lambda функція + Step Functions для автоматичного вимкнення/запуску EC2 instances з інтервалом 5 хвилин.

## 🏗️ Архітектура:

```
EventBridge (кожні 10 хв)
         ↓
   Step Functions
         ↓
    ┌────┴────┐
    │  Stop   │ (Lambda)
    └────┬────┘
         │
    Wait 5 min
         │
    ┌────┴────┐
    │  Start  │ (Lambda)
    └─────────┘
```

## 📦 Компоненти:

### 1. Lambda Functions:
- **`dev-ec2-stop`** - зупиняє EC2 instances
- **`dev-ec2-start`** - запускає EC2 instances

### 2. Step Functions Workflow:
- **Workflow**: Stop → Wait 5min → Start
- Запускається кожні 10 хвилин

### 3. EventBridge Rules:
- Trigger Step Functions workflow кожні 10 хвилин

## 🏷️ Як працює:

Lambda шукає EC2 instances з тегом:
```
Key: AutoStartStop
Value: true
```

## 📊 Цикл роботи:

```
00:00 - EventBridge triggers workflow
00:00 - Lambda зупиняє instances (Stop)
00:05 - Lambda запускає instances (Start)
00:10 - EventBridge triggers workflow знову
00:10 - Lambda зупиняє instances (Stop)
00:15 - Lambda запускає instances (Start)
... повторюється кожні 10 хвилин
```

## 🚀 Встановлення:

### 1. Deploy через Terraform:
```bash
cd infra
terraform init
terraform apply
```

### 2. Перевір що створилось:
```bash
terraform output | grep lambda
```

Output:
```
lambda_ec2_stop_function_name  = "dev-ec2-stop"
lambda_ec2_start_function_name = "dev-ec2-start"
step_functions_state_machine_arn = "arn:aws:states:us-east-1:..."
```

### 3. EC2 Instances автоматично отримують тег:
Всі instances з ASG автоматично мають:
```hcl
tags = {
  AutoStartStop = "true"
}
```

## 🔧 Управління:

### Подивитися логи Lambda:
```bash
# Stop function
aws logs tail /aws/lambda/dev-ec2-stop --follow --region us-east-1

# Start function
aws logs tail /aws/lambda/dev-ec2-start --follow --region us-east-1
```

### Подивитися Step Functions виконання:
```bash
# List executions
aws stepfunctions list-executions \
  --state-machine-arn <arn> \
  --region us-east-1

# Get execution details
aws stepfunctions describe-execution \
  --execution-arn <execution-arn> \
  --region us-east-1
```

### AWS Console:
- **Lambda**: https://console.aws.amazon.com/lambda/home?region=us-east-1
- **Step Functions**: https://console.aws.amazon.com/states/home?region=us-east-1
- **EventBridge**: https://console.aws.amazon.com/events/home?region=us-east-1

## ⚙️ Налаштування:

### Змінити інтервал:

**У `lambda.tf`:**
```hcl
# Змінити schedule
resource "aws_cloudwatch_event_rule" "trigger_step_functions" {
  schedule_expression = "rate(10 minutes)"  # ← тут
}

# Змінити затримку між stop/start
resource "aws_sfn_state_machine" "ec2_scheduler" {
  definition = jsonencode({
    States = {
      Wait5Minutes = {
        Seconds = 300  # ← тут (секунди)
      }
    }
  })
}
```

### Додати/видалити instances:

**Варіант 1: Через теги** (рекомендовано)
```bash
# Додати scheduler до instance
aws ec2 create-tags \
  --resources i-1234567890abcdef0 \
  --tags Key=AutoStartStop,Value=true \
  --region us-east-1

# Видалити з scheduler
aws ec2 delete-tags \
  --resources i-1234567890abcdef0 \
  --tags Key=AutoStartStop \
  --region us-east-1
```

**Варіант 2: В ASG** (автоматично)
Instances з ASG автоматично отримують тег при створенні.

### Вимкнути scheduler:

**Disable EventBridge Rule:**
```bash
aws events disable-rule \
  --name dev-trigger-ec2-scheduler-workflow \
  --region us-east-1
```

**Або через Terraform:**
```hcl
resource "aws_cloudwatch_event_rule" "trigger_step_functions" {
  is_enabled = false  # ← додати це
}
```

## 🔍 Troubleshooting:

### Instance не зупиняється:

1. **Перевір тег:**
```bash
aws ec2 describe-instances \
  --instance-ids i-xxxxx \
  --query 'Reservations[*].Instances[*].Tags' \
  --region us-east-1
```

2. **Перевір Lambda logs:**
```bash
aws logs tail /aws/lambda/dev-ec2-stop --follow
```

3. **Мануальний тест Lambda:**
```bash
aws lambda invoke \
  --function-name dev-ec2-stop \
  --payload '{"action":"stop"}' \
  --region us-east-1 \
  response.json

cat response.json
```

### Step Functions падає:

1. **Перевір execution history:**
AWS Console → Step Functions → Executions → Select failed execution

2. **Перевір IAM permissions:**
```bash
aws iam get-role --role-name dev-step-functions-ec2-scheduler
```

### Lambda timeout:

Збільш timeout у `lambda.tf`:
```hcl
resource "aws_lambda_function" "ec2_stop" {
  timeout = 120  # ← збільшити (секунди)
}
```

## 💰 Вартість:

- **Lambda**: ~$0.0000002 за request → **~$0.02/міс** (8,640 requests)
- **Step Functions**: ~$0.000025 за перехід → **~$0.65/міс**
- **EventBridge**: Безкоштовно

**Всього: ~$0.67/місяць**

## 🎯 Use Cases:

### 1. Dev/Test середовище:
Економія коштів - instances вимкнені частину часу.

### 2. Cost optimization:
Test Lambda scheduler before production.

### 3. Stress testing:
Перевірка як додаток реагує на restart.

## ⚠️ Важливо:

1. **ECS tasks НЕ вимикаються** - тільки EC2 instances з ASG
2. **ALB продовжує працювати** - не вимикається
3. **RDS продовжує працювати** - не зупиняється
4. **Instances перезапускаються швидко** - ~30 секунд

## 🔧 Видалити scheduler:

```bash
terraform destroy -target=aws_sfn_state_machine.ec2_scheduler
terraform destroy -target=aws_lambda_function.ec2_stop
terraform destroy -target=aws_lambda_function.ec2_start
```

Або видали весь `lambda.tf` та зроби `terraform apply`.
