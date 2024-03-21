output "log_destination" {
  value = aws_kinesis_firehose_delivery_stream.logs_to_splunk.arn
}
