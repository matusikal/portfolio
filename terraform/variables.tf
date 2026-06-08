variable "aws_region" {
  description = "Primary AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used as prefix for all resource names"
  type        = string
  default     = "portfolio"
}

variable "domain_name" {
  description = "Your custom domain name"
  type        = string
  default     = "yourdomain.xyz"  # replace with your actual domain
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket hosting the static site"
  type        = string
  default     = "yourname-portfolio-2025"  # replace with your actual bucket name
}

variable "dynamodb_table_name" {
  description = "DynamoDB table name for visitor counter"
  type        = string
  default     = "portfolio-visitor-counter"
}

variable "lambda_function_name" {
  description = "Name of the visitor counter Lambda function"
  type        = string
  default     = "portfolio-visitor-counter"
}