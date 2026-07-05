output "cloudfront_domain" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN"
  value       = aws_cloudfront_distribution.main.arn
}

output "cloudfront_hosted_zone_id" {
  description = "CloudFront hosted zone ID for Route53 alias records"
  value       = aws_cloudfront_distribution.main.hosted_zone_id
}

output "oac_id" {
  description = "Origin Access Control ID"
  value       = aws_cloudfront_origin_access_control.frontend.id
}