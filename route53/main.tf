locals {
  name        = "route53-logs-to-splunk"
}

resource "aws_route53_resolver_query_log_config" "vpc-route53-query-log-to-splunk" {
  name            = "vpc-route53-query-log-to-splunk"
  destination_arn = aws_kinesis_firehose_delivery_stream.vpc-kinesis-route53-stream-to-splunk.arn
  tags = {
    managed_by_integration = "infra/logging",
    owners                 = "Konflux/infra"
  }
}

resource "aws_route53_resolver_query_log_config_association" "vpc-route53-log-association" {
  resolver_query_log_config_id = aws_route53_resolver_query_log_config.vpc-route53-query-log-to-splunk.id
  resource_id                  = "CHANGEME"
}


module "route53_logs_to_splunk" {
  source                           = "./.."
  name                             = local.name
  cloudwatch_log_group_prefix      = "/aws/kinesisfirehose"
  cloudwatch_log_retention         = var.cloudwatch_log_retention
  firehose_splunk_retry_duration   = var.firehose_splunk_retry_duration
  hec_acknowledgment_timeout       = var.hec_acknowledgment_timeout
  hec_token                        = var.hec_token
  kinesis_firehose_buffer          = var.kinesis_firehose_buffer
  kinesis_firehose_buffer_interval = var.kinesis_firehose_buffer_interval
  log_group_tags                   = var.log_group_tags
  log_stream_name                  = var.log_stream_name
  s3_backup_mode                   = var.s3_backup_mode
  s3_compression_format            = var.s3_compression_format
  s3_prefix                        = var.s3_prefix
  splunk_endpoint                  = var.splunk_endpoint
  tags                             = var.tags
}
