output "delivery_stream_arn" {
  description = "ARN of the Firehose delivery stream."
  value       = module.firehose.log_destination
}

output "delivery_stream_name" {
  description = "Name of the Firehose delivery stream."
  value       = module.firehose.delivery_stream_name
}

output "backup_bucket_name" {
  description = "Name of the S3 bucket used for backup and failed events."
  value       = module.firehose.backup_bucket_name
}

output "subscription_filter_name" {
  description = "Name of the CloudWatch Logs subscription filter."
  value       = aws_cloudwatch_log_subscription_filter.this.name
}

output "cloudwatch_logs_role_arn" {
  description = "ARN of the IAM role assumed by CloudWatch Logs to publish to Firehose."
  value       = aws_iam_role.cloudwatch_logs_to_firehose.arn
}

output "required_splunk_hec_metadata" {
  description = "Metadata that must be configured as defaults on the dedicated Splunk HEC token. Runtime end-to-end testing must verify these values."
  value = {
    host       = var.splunk_host
    index      = var.splunk_index
    source     = var.source_id
    sourcetype = var.splunk_sourcetype
  }
}
