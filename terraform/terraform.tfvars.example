# =============================================================================
# terraform.tfvars – Fill in your actual values
# DO NOT commit this file to Git (it's in .gitignore)
# =============================================================================

# Your domain (must already have a Route 53 Hosted Zone)
domain_name     = "yourname.dev"
www_domain_name = "www.yourname.dev"   # Set to "" to skip

# S3 bucket name – must be globally unique
s3_bucket_name = "yourname-portfolio-prod-site"

# -----------------------------------------------------------------------
# WAF Free Tier fix:
# Paste your existing CloudFront distribution ID here, then run:
#   terraform import aws_cloudfront_distribution.site <DISTRIBUTION_ID>
# Terraform will adopt the existing distribution without recreating it.
# -----------------------------------------------------------------------
existing_cloudfront_distribution_id = "E1ABCDEF2GHIJK"   # ← your distro ID

# Paste the WAF WebACL ARN that is currently locked to your CloudFront.
# By declaring it here, Terraform keeps the association and won't fight it.
# Get it from: AWS Console → WAF → WebACLs → (your ACL) → ARN
waf_web_acl_arn = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/your-acl-name/abc-123"

# Optional overrides (defaults are fine for most cases)
# aws_region            = "eu-central-1"
# environment           = "prod"
# project_name          = "portfolio"
# dynamodb_table_name   = "portfolio-visitor-counter"
# lambda_function_name  = "portfolio-visitor-counter"
# api_gateway_name      = "portfolio-api"
# enable_kms            = true
# cloudfront_price_class = "PriceClass_100"
