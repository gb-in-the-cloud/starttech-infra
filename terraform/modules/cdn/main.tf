# ─── Origin Access Control (OAC) ─────────────────────────────────────────────
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.project_name}-oac"
  description                       = "OAC for ${var.project_name} S3 frontend bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ─── CloudFront Distribution ──────────────────────────────────────────────────
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name} CloudFront Distribution"
  default_root_object = "index.html"

  # ─── S3 Origin (Frontend) ──────────────────────────────────────────────────
  origin {
    origin_id                = "S3-Frontend"
    domain_name              = var.s3_bucket_domain
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # ─── ALB Origin (Backend API) ──────────────────────────────────────────────
  origin {
    origin_id   = "ALB-Backend"
    domain_name = var.alb_dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # ─── Default Cache Behavior → S3 Frontend ──────────────────────────────────
  default_cache_behavior {
    target_origin_id       = "S3-Frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  # ─── Ordered Cache Behavior → ALB Backend (/api/*) ─────────────────────────
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "ALB-Backend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # Bypass caching for API requests
    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies {
        forward = "all"
      }
    }

    # TTL set to 0 to bypass caching
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  # ─── Custom Error Responses ────────────────────────────────────────────────
  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  # ─── Geo Restrictions ──────────────────────────────────────────────────────
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # ─── SSL Certificate ───────────────────────────────────────────────────────
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name        = "${var.project_name}-cloudfront"
    Environment = var.environment
  }
}

# ─── S3 Bucket Policy — Allow CloudFront OAC Only ────────────────────────────
resource "aws_s3_bucket_policy" "frontend" {
  bucket = var.s3_bucket_id

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
        Resource = "${var.s3_bucket_arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      }
    ]
  })
}