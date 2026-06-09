# =============================================================================
# outputs.tf – All useful values after `terraform apply`
# =============================================================================

output "site_bucket_name" {
  description = "S3 bucket name – sync your build output here"
  value       = aws_s3_bucket.site.id
}

output "site_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.site.arn
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID – needed for cache invalidations in CI/CD"
  value       = aws_cloudfront_distribution.site.id
}

output "cloudfront_distribution_domain" {
  description = "CloudFront default domain (*.cloudfront.net) – point Namecheap CNAME here"
  value       = aws_cloudfront_distribution.site.domain_name
}

output "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN"
  value       = aws_cloudfront_distribution.site.arn
}

output "site_url" {
  description = "Live URL of your portfolio site"
  value       = "https://${var.domain_name}"
}

output "api_endpoint" {
  description = "API Gateway base URL – visitor counter calls go to {api_endpoint}/count"
  value       = aws_apigatewayv2_stage.prod.invoke_url
}

output "visitor_counter_endpoint" {
  description = "Full visitor counter endpoint (GET increments and returns count)"
  value       = "${aws_apigatewayv2_stage.prod.invoke_url}/count"
}

output "dynamodb_table_name" {
  description = "DynamoDB table name for visitor counter"
  value       = aws_dynamodb_table.visitor_counter.name
}

output "dynamodb_table_arn" {
  description = "DynamoDB table ARN"
  value       = aws_dynamodb_table.visitor_counter.arn
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.visitor_counter.function_name
}

output "lambda_function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.visitor_counter.arn
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN (us-east-1) – attached to CloudFront"
  value       = aws_acm_certificate.site.arn
}

# =============================================================================
# ACM Validation – CNAME records to add manually in Namecheap
# Run after: terraform apply -target=aws_acm_certificate.site
# =============================================================================
output "acm_validation_records" {
  description = "CNAME records to add in Namecheap Advanced DNS to validate your ACM certificate"
  value = {
    for dvo in aws_acm_certificate.site.domain_validation_options : dvo.domain_name => {
      type  = dvo.resource_record_type
      name  = dvo.resource_record_name
      value = dvo.resource_record_value
    }
  }
}

output "namecheap_dns_instructions" {
  description = "What to configure in Namecheap after apply"
  value       = "www CNAME → ${aws_cloudfront_distribution.site.domain_name} | Apex ALIAS/ANAME → ${aws_cloudfront_distribution.site.domain_name}"
}

output "kms_key_arn" {
  description = "KMS CMK ARN (null if KMS disabled)"
  value       = var.enable_kms ? aws_kms_key.portfolio[0].arn : null
}

output "kms_key_alias" {
  description = "KMS CMK alias"
  value       = var.enable_kms ? aws_kms_alias.portfolio[0].name : null
}

# =============================================================================
# GitHub Actions CI/CD credentials
# Store these as GitHub repository secrets immediately after first apply
# =============================================================================
output "github_actions_access_key_id" {
  description = "GitHub Actions IAM access key ID → GitHub secret: AWS_ACCESS_KEY_ID"
  value       = aws_iam_access_key.github_actions.id
  sensitive   = false
}

output "github_actions_secret_access_key" {
  description = "GitHub Actions IAM secret access key → GitHub secret: AWS_SECRET_ACCESS_KEY"
  value       = aws_iam_access_key.github_actions.secret
  sensitive   = true
}

# =============================================================================
# Quick-reference: GitHub Actions environment variables block
# =============================================================================
output "github_actions_env_block" {
  description = "Paste this env block into your GitHub Actions workflow"
  sensitive   = false
  value       = <<-EOT
    # Add these as GitHub repository secrets:
    # AWS_ACCESS_KEY_ID     = ${aws_iam_access_key.github_actions.id}
    # AWS_REGION            = ${var.aws_region}
    # S3_BUCKET             = ${aws_s3_bucket.site.id}
    # CLOUDFRONT_DIST_ID    = ${aws_cloudfront_distribution.site.id}
    # API_ENDPOINT          = ${aws_apigatewayv2_stage.prod.invoke_url}/count
  EOT
}
