output "cloudfront_domain" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.portfolio.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID — needed for GitHub Actions"
  value       = aws_cloudfront_distribution.portfolio.id
}

output "s3_bucket_name" {
  description = "S3 bucket name — needed for GitHub Actions"
  value       = aws_s3_bucket.portfolio.bucket
}

output "api_gateway_url" {
  description = "Full API Gateway URL for the visitor counter"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/counter"
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.visitor_counter.function_name
}

output "dynamodb_table_name" {
  description = "DynamoDB table name"
  value       = aws_dynamodb_table.visitor_counter.name
}