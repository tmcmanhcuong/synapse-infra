################################################################################
# Edge Module - Outputs
################################################################################

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "alb_target_group_api_arn" {
  description = "ARN of the API target group for ECS service attachment"
  value       = aws_lb_target_group.api.arn
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID for cache invalidation"
  value       = aws_cloudfront_distribution.main.id
}

output "s3_web_bucket_name" {
  description = "Name of the S3 bucket hosting the SPA"
  value       = aws_s3_bucket.web.id
}

output "s3_web_bucket_arn" {
  description = "ARN of the S3 bucket hosting the SPA"
  value       = aws_s3_bucket.web.arn
}

output "alb_arn_suffix" {
  description = "ARN suffix of the ALB for CloudWatch metrics"
  value       = aws_lb.main.arn_suffix
}

output "target_group_arn_suffix" {
  description = "ARN suffix of the API target group for CloudWatch metrics"
  value       = aws_lb_target_group.api.arn_suffix
}
