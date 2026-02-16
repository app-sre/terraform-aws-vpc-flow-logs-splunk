output "log_destination" {
  value = var.destination_type == "splunk" ? aws_kinesis_firehose_delivery_stream.logs_to_splunk[0].arn : aws_kinesis_firehose_delivery_stream.logs_to_http_endpoint[0].arn
}
