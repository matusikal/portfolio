variable "aws_region" {
  description = "Primary AWS region for all resources except ACM/WAF (eu-central-1 for GDPR compliance)"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Project name used for naming and tagging all resources"
  type        = string
  default     = "portfolio"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod"
}

variable "domain_name" {
  description = "Your root domain name (e.g. example.com)"
  type        = string
  # No default – must be set in terraform.tfvars
}

variable "www_domain_name" {
  description = "www subdomain (e.g. www.example.com). Leave empty to skip www redirect."
  type        = string
  default     = ""
}

variable "existing_cloudfront_distribution_id" {
  description = <<EOT
ID of your EXISTING CloudFront distribution (e.g. E1ABCDEF2GHIJK).
Set this if you already have a distribution you want Terraform to import and manage.
Leave empty ("") if you want Terraform to create a brand-new distribution.
EOT
  type        = string
  default     = ""
}

variable "waf_web_acl_arn" {
  description = <<EOT
ARN of the existing WAF WebACL to associate with CloudFront.
Must be in us-east-1. Leave empty ("") to skip WAF association.
Example: arn:aws:wafv2:us-east-1:123456789012:global/webacl/my-acl/abc123
EOT
  type        = string
  default     = ""
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for static site hosting (must be globally unique)"
  type        = string
  # Recommended: "${var.project_name}-${var.environment}-site-${random_suffix}"
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table for visitor counter"
  type        = string
  default     = "portfolio-visitor-counter"
}

variable "lambda_function_name" {
  description = "Name of the Lambda function for visitor counter API"
  type        = string
  default     = "portfolio-visitor-counter"
}

variable "api_gateway_name" {
  description = "Name of the API Gateway HTTP API"
  type        = string
  default     = "portfolio-api"
}

variable "enable_kms" {
  description = "Encrypt DynamoDB table and S3 bucket with a customer-managed KMS key"
  type        = bool
  default     = true
}

variable "cloudfront_price_class" {
  description = "CloudFront price class. PriceClass_100 = EU+NA only (cheapest, good for EU users)"
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "Must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}

variable "github_actions_user_name" {
  description = "IAM user name for GitHub Actions CI/CD deployments"
  type        = string
  default     = "github-actions-portfolio"
}
