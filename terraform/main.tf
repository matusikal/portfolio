# =============================================================================
# main.tf – Serverless Portfolio: S3 + CloudFront + Lambda + API GW + DynamoDB
# Region strategy:
#   Primary resources  → eu-central-1 (Frankfurt) – GDPR / EU market
#   ACM cert + WAF     → us-east-1 (required by CloudFront)
# =============================================================================

locals {
  # Build a unique suffix from account ID for globally-unique names
  bucket_name    = var.s3_bucket_name
  lambda_zip_dir = "${path.module}/.lambda_build"
}

# =============================================================================
# KMS – Customer Managed Key (eu-central-1)
# =============================================================================
resource "aws_kms_key" "portfolio" {
  count               = var.enable_kms ? 1 : 0
  description         = "${var.project_name} CMK – encrypts S3, DynamoDB, Lambda env vars"
  enable_key_rotation = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Principal = { Service = "logs.${var.aws_region}.amazonaws.com" }
        Action = [
          "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
          "kms:GenerateDataKey*", "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "portfolio" {
  count         = var.enable_kms ? 1 : 0
  name          = "alias/${var.project_name}-${var.environment}"
  target_key_id = aws_kms_key.portfolio[0].key_id
}

# =============================================================================
# S3 – Static Website Bucket (eu-central-1)
# =============================================================================
resource "aws_s3_bucket" "site" {
  bucket = local.bucket_name

  lifecycle {
    prevent_destroy = true # Protect against accidental `terraform destroy`
  }
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_kms ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms ? aws_kms_key.portfolio[0].arn : null
    }
    bucket_key_enabled = var.enable_kms ? true : false
  }
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# OAC – Origin Access Control (replaces legacy OAI)
resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.project_name}-${var.environment}-oac"
  description                       = "OAC for ${var.project_name} S3 origin"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# S3 bucket policy – only allows CloudFront OAC to read objects
resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.site.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.site.arn
          }
        }
      }
    ]
  })
}

# =============================================================================
# ACM – TLS Certificate (must be in us-east-1 for CloudFront)
# =============================================================================
resource "aws_acm_certificate" "site" {
  provider          = aws.us_east_1
  domain_name       = var.domain_name
  validation_method = "DNS"

  subject_alternative_names = var.www_domain_name != "" ? [var.www_domain_name] : []

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# ACM DNS Validation – MANUAL (Namecheap DNS)
# -----------------------------------------------------------------------------
# After running: terraform apply -target=aws_acm_certificate.site
#
# Run this to get the CNAME records to add in Namecheap:
#   terraform output acm_validation_records
#
# In Namecheap → Domain List → Manage → Advanced DNS → Add New Record:
#   Type  : CNAME Record
#   Host  : <name> WITHOUT your domain suffix and without trailing dot
#           e.g. "_abc123def456.yourname.dev." → host = "_abc123def456"
#   Value : <value> WITHOUT trailing dot
#           e.g. "_xyz.acm-validations.aws." → value = "_xyz.acm-validations.aws"
#   TTL   : Automatic
#
# Wait ~5-30 min for ACM to show "Issued", then run: terraform apply
# =============================================================================

# Tells Terraform to wait until ACM reports the cert as valid.
# validation_record_fqdns is left empty because Namecheap manages the DNS –
# Terraform has no way to verify the records exist, so ACM does it itself.
resource "aws_acm_certificate_validation" "site" {
  provider        = aws.us_east_1
  certificate_arn = aws_acm_certificate.site.arn

  timeouts {
    create = "45m"
  }
}

# =============================================================================
# CloudFront Distribution
# -----------------------------------------------------------------------------
# IMPORTANT – WAF Free Tier lock workaround:
#
# If you already have a CloudFront distribution that is locked to a WAF WebACL
# (because you chose "Free" pricing on WAF and can't disassociate it), you have
# two options:
#
# OPTION A – Import your existing distribution (recommended):
#   Run once BEFORE `terraform apply`:
#   terraform import aws_cloudfront_distribution.site <YOUR_DISTRIBUTION_ID>
#   Terraform will then manage (not recreate) the existing distribution.
#
# OPTION B – Delete the WAF WebACL first (if you want a clean slate):
#   1. In the WAF console, delete all rules from the WebACL.
#   2. AWS will eventually allow disassociation – or just let Terraform
#      overwrite the association via import (Option A).
#
# Either way, set var.waf_web_acl_arn to keep the association in state.
# =============================================================================
resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name} – ${var.environment}"
  default_root_object = "index.html"
  price_class         = var.cloudfront_price_class
  aliases             = var.www_domain_name != "" ? [var.domain_name, var.www_domain_name] : [var.domain_name]

  # Attach WAF WebACL – handles Free-tier lock by declaring it explicitly
  # Set var.waf_web_acl_arn = "" to remove association
  web_acl_id = var.waf_web_acl_arn != "" ? var.waf_web_acl_arn : null

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "S3-${local.bucket_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${local.bucket_name}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_optimized.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.cors_s3origin.id
  }

  # SPA / static site – return index.html on 403/404 (handles React Router etc.)
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.site.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  depends_on = [aws_acm_certificate_validation.site]
}

# =============================================================================
# DNS – Managed by Namecheap (not Terraform)
# -----------------------------------------------------------------------------
# After terraform apply completes, point your domain at CloudFront in Namecheap:
#
#   Domain List → Manage → Advanced DNS → Add New Record:
#
#   For APEX (yourname.dev):
#     Namecheap does not support ALIAS/ANAME natively on all plans.
#     Option A (recommended): Use CNAME flattening – some registrars call it
#       "ALIAS" or "ANAME". Host = "@", Value = CloudFront domain from output.
#     Option B: Use Namecheap's "URL Redirect" to www, then www → CNAME.
#     Option C: Upgrade to Namecheap PremiumDNS which supports ALIAS records.
#
#   For WWW (www.yourname.dev):
#     Type  : CNAME Record
#     Host  : www
#     Value : <cloudfront_distribution_domain from terraform output>
#     TTL   : Automatic
#
# Get the CloudFront domain after apply: terraform output cloudfront_distribution_domain
# =============================================================================

# =============================================================================
# DynamoDB – Visitor Counter Table (eu-central-1)
# =============================================================================
resource "aws_dynamodb_table" "visitor_counter" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  dynamic "server_side_encryption" {
    for_each = var.enable_kms ? [1] : []
    content {
      enabled     = true
      kms_key_arn = aws_kms_key.portfolio[0].arn
    }
  }
}

# Seed the counter item so the Lambda never gets a missing-key error
resource "aws_dynamodb_table_item" "visitor_counter_seed" {
  table_name = aws_dynamodb_table.visitor_counter.name
  hash_key   = aws_dynamodb_table.visitor_counter.hash_key

  item = jsonencode({
    id      = { S = "visitors" }
    counter = { N = "0" }
  })

  lifecycle {
    ignore_changes = [item] # Don't reset counter on every apply
  }
}

# =============================================================================
# IAM – Lambda Execution Role
# =============================================================================
resource "aws_iam_role" "lambda_exec" {
  name = "${var.lambda_function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "${var.lambda_function_name}-dynamodb"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:PutItem"
        ]
        Resource = aws_dynamodb_table.visitor_counter.arn
      },
      # KMS decrypt permission if CMK is enabled
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = var.enable_kms ? aws_kms_key.portfolio[0].arn : "*"
        Condition = var.enable_kms ? {} : {
          StringEquals = { "kms:ViaService" : "dynamodb.${var.aws_region}.amazonaws.com" }
        }
      }
    ]
  })
}

# =============================================================================
# Lambda – Visitor Counter Function (eu-central-1)
# The ZIP is built from ./lambda/visitor_counter.py
# =============================================================================
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/visitor_counter.py"
  output_path = "${path.module}/.lambda_build/visitor_counter.zip"
}

resource "aws_lambda_function" "visitor_counter" {
  function_name    = var.lambda_function_name
  role             = aws_iam_role.lambda_exec.arn
  handler          = "visitor_counter.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.visitor_counter.name
      ITEM_ID    = "visitors"
    }
  }

  dynamic "kms_key_arn" {
    for_each = [] # kms_key_arn is a top-level arg, not a block – see below
  }

  kms_key_arn = var.enable_kms ? aws_kms_key.portfolio[0].arn : null

  depends_on = [aws_iam_role_policy_attachment.lambda_basic]
}

# Lambda log group with retention
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 30

  dynamic "kms_key_id" {
    for_each = [] # not a block – handled below
  }

  kms_key_id = var.enable_kms ? aws_kms_key.portfolio[0].arn : null
}

# Lambda permission – allow API GW to invoke it
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitor_counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.portfolio.execution_arn}/*/*"
}

# =============================================================================
# API Gateway – HTTP API (eu-central-1)
# =============================================================================
resource "aws_apigatewayv2_api" "portfolio" {
  name          = var.api_gateway_name
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers  = ["Content-Type"]
    allow_methods  = ["GET", "POST", "OPTIONS"]
    allow_origins  = ["https://${var.domain_name}"]
    expose_headers = []
    max_age        = 300
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id             = aws_apigatewayv2_api.portfolio.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.visitor_counter.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "get_count" {
  api_id    = aws_apigatewayv2_api.portfolio.id
  route_key = "GET /count"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "post_count" {
  api_id    = aws_apigatewayv2_api.portfolio.id
  route_key = "POST /count"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.portfolio.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
  }
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name              = "/aws/apigateway/${var.api_gateway_name}"
  retention_in_days = 30
}

# =============================================================================
# IAM – GitHub Actions CI/CD User (eu-central-1)
# Least-privilege: can only sync to the site bucket and invalidate CloudFront
# =============================================================================
resource "aws_iam_user" "github_actions" {
  name = var.github_actions_user_name
}

resource "aws_iam_access_key" "github_actions" {
  user = aws_iam_user.github_actions.name
}

resource "aws_iam_user_policy" "github_actions" {
  name = "${var.github_actions_user_name}-policy"
  user = aws_iam_user.github_actions.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Sync"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetObject"
        ]
        Resource = [
          aws_s3_bucket.site.arn,
          "${aws_s3_bucket.site.arn}/*"
        ]
      },
      {
        Sid      = "CloudFrontInvalidate"
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation"]
        Resource = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/${aws_cloudfront_distribution.site.id}"
      }
    ]
  })
}

# =============================================================================
# Data Sources
# =============================================================================
data "aws_caller_identity" "current" {}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_origin_request_policy" "cors_s3origin" {
  name = "Managed-CORS-S3Origin"
}
