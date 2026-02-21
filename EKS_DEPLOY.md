# EKS + Helm Deploy Guide

## Структура проекту

```
infra/
  eks.tf          ← EKS кластер, node group, OIDC, add-ons, IAM ролі
  vpc.tf          ← VPC, subnets, NAT
  sg.tf           ← Security Groups (ALB, EC2, RDS, EKS nodes)
  alb.tf          ← Application Load Balancer
  ecr.tf          ← ECR репозиторій для Docker образів
  providers.tf    ← AWS provider
  variables.tf    ← Змінні
  outputs.tf      ← Outputs (EKS endpoint, ECR URL тощо)

helm/
  title-checker/
    Chart.yaml                      ← Метадані chart-у
    values.yaml                     ← Налаштування (образ, реплік, ресурси тощо)
    templates/
      _helpers.tpl                  ← Допоміжні функції
      deployment.yaml               ← Kubernetes Deployment
      service.yaml                  ← Kubernetes Service (ClusterIP)
      ingress.yaml                  ← Kubernetes Ingress (AWS ALB)
      hpa.yaml                      ← HorizontalPodAutoscaler
      serviceaccount.yaml           ← ServiceAccount
```

---

## Крок 1 — Terraform: розгортаємо EKS кластер

```bash
cd infra

# Ініціалізація (перший раз або після зміни провайдерів)
terraform init

# Перевірка плану
terraform plan

# Застосування
terraform apply
```

> ⏱ EKS кластер стартує ~10-15 хвилин.

---

## Крок 2 — Отримуємо kubeconfig

```bash
# Команда береться з terraform output
aws eks update-kubeconfig --region us-east-1 --name dev-eks-cluster

# Перевірка
kubectl get nodes
```

---

## Крок 3 — Збираємо і пушимо Docker образ у ECR

```bash
# ECR URL береться з terraform output ecr_repository_url
ECR_URL=$(terraform output -raw ecr_repository_url)

# Логінимось у ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin $ECR_URL

# Збираємо образ
docker build -t title-checker ./app

# Тегуємо
docker tag title-checker:latest $ECR_URL:latest

# Пушимо
docker push $ECR_URL:latest
```

---

## Крок 4 — Встановлюємо AWS Load Balancer Controller (потрібен для Ingress)

```bash
# Встановлюємо cert-manager (залежність)
kubectl apply --validate=false -f \
  https://github.com/jetstack/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Додаємо Helm репо
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Встановлюємо AWS LB Controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=dev-eks-cluster \
  --set serviceAccount.create=true \
  --set region=us-east-1 \
  --set vpcId=$(terraform output -raw vpc_id)
```

---

## Крок 5 — helm install (деплой застосунку)

```bash
cd ..   # корінь проекту

# Перший деплой
helm install title-checker ./helm/title-checker \
  --namespace default \
  --set image.repository=$(cd infra && terraform output -raw ecr_repository_url) \
  --set image.tag=latest

# Перевірка стану
kubectl get pods
kubectl get svc
kubectl get ingress
```

---

## Крок 6 — Оновлення застосунку (після нового образу)

```bash
# Після docker push нового образу:
helm upgrade title-checker ./helm/title-checker \
  --namespace default \
  --set image.tag=latest

# або з новим тегом версії:
helm upgrade title-checker ./helm/title-checker \
  --set image.tag=v1.2.0
```

---

## Корисні команди

```bash
# Статус Helm release-у
helm status title-checker

# Переглянути всі release-и
helm list

# Видалити застосунок (але не EKS!)
helm uninstall title-checker

# Видалити EKS (через Terraform)
cd infra && terraform destroy
```

---

## Outputs після terraform apply

| Output | Опис |
|--------|------|
| `eks_cluster_name` | Назва кластера |
| `eks_cluster_endpoint` | API endpoint кластера |
| `eks_kubeconfig_command` | Команда для kubeconfig |
| `ecr_repository_url` | URL ECR для docker push |
| `eks_oidc_provider_arn` | ARN OIDC (для IRSA) |
