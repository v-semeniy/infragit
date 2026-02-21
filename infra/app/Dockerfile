FROM python:3.11

WORKDIR /app

COPY title_checker.py .

RUN pip install flask pandas python-docx werkzeug

RUN mkdir uploads

EXPOSE 8501

CMD ["python", "title_checker.py"]

# PSEUDO CODE: CI/CD PIPELINE

# 1. Developer pushes code to Git repository

# 2. CI/CD pipeline starts (GitLab CI, GitHub Actions, Jenkins, etc.)

# 3. Steps:
#    a. Checkout code
#    b. Run unit tests
#    c. Build Docker image:
#       - docker build -t title_checker .
#    d. Push Docker image to registry (DockerHub, ECR, etc.)
#       - docker push <registry>/title_checker:latest
#    e. Upload Python file (title_checker.py) to S3 (optional)
#       - aws s3 cp title_checker.py s3://bucket123ultra/title_checker.py
#    f. Run Terraform to deploy infrastructure:
#       - terraform init
#       - terraform plan
#       - terraform apply -auto-approve