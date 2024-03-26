locals {
  name_prefix = length(var.vpc_name) > 0 ? var.vpc_name : var.vpc_id
  name        = "${local.name_prefix}-vpc-logs-to-splunk"
}

resource "aws_flow_log" "vpc" {
  log_destination          = module.vpc_logs_to_splunk.log_destination
  log_destination_type     = "kinesis-data-firehose"
  traffic_type             = "ALL"
  vpc_id                   = var.vpc_id
  max_aggregation_interval = var.flow_log_max_aggregation_interval
  log_format               = var.log_format
}

module "vpc_logs_to_splunk" {
  source                           = "./modules/splunk-firehose-connection"
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
