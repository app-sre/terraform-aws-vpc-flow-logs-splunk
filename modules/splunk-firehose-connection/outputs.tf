output "log_destination" {
  description = "ARN of the selected Firehose delivery stream."
  value       = var.destination_type == "splunk" ? aws_kinesis_firehose_delivery_stream.logs_to_splunk[0].arn : aws_kinesis_firehose_delivery_stream.logs_to_http_endpoint[0].arn
}

output "delivery_stream_name" {
  description = "Name of the selected Firehose delivery stream."
  value       = var.destination_type == "splunk" ? aws_kinesis_firehose_delivery_stream.logs_to_splunk[0].name : aws_kinesis_firehose_delivery_stream.logs_to_http_endpoint[0].name
}

output "backup_bucket_name" {
  description = "Name of the S3 bucket used for Firehose backup and failed events."
  value       = aws_s3_bucket.kinesis_firehose.id
}
