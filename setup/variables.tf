variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 super"
  type        = string
  default     = "t2.micro"
}

variable "ami" {
  description = "AMI ID"
  type        = string
}