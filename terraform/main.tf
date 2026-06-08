# ══════════════════════════════════════════════
# S3 BUCKET — static site hosting
# ══════════════════════════════════════════════

resource "aws_s3_bucket" "portfolio" {
  bucket = var.s3_bucket_name

  tags = {
    Project     = var.project_name
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# Block all public access — CloudFront accesses it privately via OAC
resource "aws_s3_bucket_public_access_block" "portfolio" {
  bucket = aws_s3_bucket.portfolio.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning — lets you roll back to previous versions of your site
resource "aws_s3_bucket_versioning" "portfolio" {
  bucket = aws_s3_bucket.portfolio.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ══════════════════════════════════════════════
# CLOUDFRONT OAC — lets CloudFront access S3 privately
# ══════════════════════════════════════════════

resource "aws_cloudfront_origin_access_control" "portfolio" {
  name                              = "${var.project_name}-oac"
  description                       = "OAC for portfolio S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ══════════════════════════════════════════════
# ACM CERTIFICATE — must be in us-east-1 for CloudFront
# ══════════════════════════════════════════════

resource "aws_acm_certificate" "portfolio" {
  provider          = aws.us_east_1  # hard AWS requirement for CloudFront
  domain_name       = var.domain_name
  validation_method = "DNS"

  subject_alternative_names = [
    "www.${var.domain_name}"
  ]

  lifecycle {
    create_before_destroy = true  # prevents downtime when renewing
  }

  tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

# ══════════════════════════════════════════════
# CLOUDFRONT DISTRIBUTION
# ══════════════════════════════════════════════

resource "aws_cloudfront_distribution" "portfolio" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [var.domain_name, "www.${var.domain_name}"]
  price_class         = "PriceClass_100"  # Europe + North America only — cheapest option

  # Where CloudFront pulls content from — your S3 bucket
  origin {
    domain_name              = aws_s3_bucket.portfolio.bucket_regional_domain_name
    origin_id                = "S3-${var.s3_bucket_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.portfolio.id
  }

  # Default behaviour — how CloudFront handles requests
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${var.s3_bucket_name}"
    viewer_protocol_policy = "redirect-to-https"  # HTTP → HTTPS automatically
    compress               = true                  # gzip compression for faster loads

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600   # cache for 1 hour by default
    max_ttl     = 86400  # max cache 24 hours
  }

  # SSL certificate
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.portfolio.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"  # modern TLS only, older versions blocked
  }

  # WAF association
  web_acl_id = aws_wafv2_web_acl.portfolio.arn

  restrictions {
    geo_restriction {
      restriction_type = "none"  # allow all countries
    }
  }

  tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
  }

  # Wait for certificate before creating distribution
  depends_on = [aws_acm_certificate.portfolio]
}

# S3 bucket policy — allows only CloudFront to read the bucket
resource "aws_s3_bucket_policy" "portfolio" {
  bucket = aws_s3_bucket.portfolio.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.portfolio.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.portfolio.arn
          }
        }
      }
    ]
  })
}

# ══════════════════════════════════════════════
# WAF — Web Application Firewall
# ══════════════════════════════════════════════

resource "aws_wafv2_web_acl" "portfolio" {
  provider    = aws.us_east_1  # WAF for CloudFront must be in us-east-1
  name        = "${var.project_name}-waf"
  description = "WAF for portfolio CloudFront distribution"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}  # allow everything unless a rule blocks it
  }

  # Rule 1: IP Reputation List
  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesAmazonIpReputationList"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: Common Rule Set (OWASP Top 10)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3: Known Bad Inputs
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "portfolio-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

# ══════════════════════════════════════════════
# DYNAMODB — visitor counter table
# ══════════════════════════════════════════════

resource "aws_dynamodb_table" "visitor_counter" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"  # on-demand — you pay per request, not per hour
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"  # S = String
  }

  # AWS owned encryption key — free, encrypts all data at rest
  server_side_encryption {
    enabled = true
  }

  tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

# ══════════════════════════════════════════════
# IAM — Lambda execution role (least privilege)
# ══════════════════════════════════════════════

# The role itself — defines who can assume it (Lambda service)
resource "aws_iam_role" "lambda_execution" {
  name = "${var.project_name}-lambda-execution-role"

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
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

# Custom policy — only the exact permissions Lambda needs
resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "${var.project_name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Only UpdateItem and GetItem on this specific table
        # Not full DynamoDB access — true least privilege
        Effect = "Allow"
        Action = [
          "dynamodb:UpdateItem",
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.visitor_counter.arn
      }
    ]
  })
}

# Basic Lambda logging permission — lets Lambda write to CloudWatch
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ══════════════════════════════════════════════
# LAMBDA — visitor counter function
# ══════════════════════════════════════════════

# Package the Python file into a zip — Lambda requires a zip file
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "visitor_counter" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.lambda_function_name
  role             = aws_iam_role.lambda_execution.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = var.dynamodb_table_name
    }
  }

  tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

# ══════════════════════════════════════════════
# API GATEWAY — REST API for the counter
# ══════════════════════════════════════════════

resource "aws_api_gateway_rest_api" "portfolio" {
  name        = "${var.project_name}-api"
  description = "REST API for portfolio visitor counter"

  tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

# /counter resource
resource "aws_api_gateway_resource" "counter" {
  rest_api_id = aws_api_gateway_rest_api.portfolio.id
  parent_id   = aws_api_gateway_rest_api.portfolio.root_resource_id
  path_part   = "counter"
}

# POST method on /counter
resource "aws_api_gateway_method" "counter_post" {
  rest_api_id   = aws_api_gateway_rest_api.portfolio.id
  resource_id   = aws_api_gateway_resource.counter.id
  http_method   = "POST"
  authorization = "NONE"
}

# Connect POST method to Lambda
resource "aws_api_gateway_integration" "counter_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.portfolio.id
  resource_id             = aws_api_gateway_resource.counter.id
  http_method             = aws_api_gateway_method.counter_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"  # proxy integration — Lambda controls the full response
  uri                     = aws_lambda_function.visitor_counter.invoke_arn
}

# OPTIONS method for CORS preflight requests
resource "aws_api_gateway_method" "counter_options" {
  rest_api_id   = aws_api_gateway_rest_api.portfolio.id
  resource_id   = aws_api_gateway_resource.counter.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "counter_options" {
  rest_api_id = aws_api_gateway_rest_api.portfolio.id
  resource_id = aws_api_gateway_resource.counter.id
  http_method = aws_api_gateway_method.counter_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "counter_options_200" {
  rest_api_id = aws_api_gateway_rest_api.portfolio.id
  resource_id = aws_api_gateway_resource.counter.id
  http_method = aws_api_gateway_method.counter_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "counter_options" {
  rest_api_id = aws_api_gateway_rest_api.portfolio.id
  resource_id = aws_api_gateway_resource.counter.id
  http_method = aws_api_gateway_method.counter_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_integration.counter_options]
}

# Deploy the API to prod stage
resource "aws_api_gateway_deployment" "portfolio" {
  rest_api_id = aws_api_gateway_rest_api.portfolio.id

  # Force redeployment when any method or integration changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.counter.id,
      aws_api_gateway_method.counter_post.id,
      aws_api_gateway_integration.counter_lambda.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.portfolio.id
  rest_api_id   = aws_api_gateway_rest_api.portfolio.id
  stage_name    = "prod"

  tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

# Permission for API Gateway to invoke Lambda
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitor_counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.portfolio.execution_arn}/*/*"
}