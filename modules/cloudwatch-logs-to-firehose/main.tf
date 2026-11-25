data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

locals {
  cloudwatch_logs_principal = "logs.${data.aws_partition.current.dns_suffix}"
  source_log_group_arn      = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${var.cloudwatch_log_group_name}"
  subscription_filter_name  = coalesce(var.subscription_filter_name, "${var.name}-to-firehose")
  cloudwatch_role_name      = "${var.name}-cwlogs"

  source_tags = merge(
    var.tags,
    {
      Environment = var.environment
      LogSource   = var.source_id
      Service     = var.service_name
    },
  )
}

module "firehose" {
  source = "../splunk-firehose-connection"

  name                               = var.name
  cloudwatch_logs_source             = true
  cloudwatch_log_group_prefix        = "/aws/kinesisfirehose"
  cloudwatch_log_retention           = var.cloudwatch_log_retention
  firehose_splunk_retry_duration     = var.firehose_splunk_retry_duration
  hec_acknowledgment_timeout         = var.hec_acknowledgment_timeout
  kinesis_firehose_buffer            = var.kinesis_firehose_buffer
  kinesis_firehose_buffer_interval   = var.kinesis_firehose_buffer_interval
  log_group_tags                     = var.log_group_tags
  log_stream_name                    = var.log_stream_name
  splunk_s3_backup_mode              = var.splunk_s3_backup_mode
  s3_compression_format              = var.s3_compression_format
  s3_bucket_name                     = "${var.name}-${substr(sha256("${data.aws_caller_identity.current.account_id}:${data.aws_region.current.name}"), 0, 12)}"
  s3_prefix                          = var.s3_prefix
  s3_lifecycle_expiration_days       = var.s3_lifecycle_expiration_days
  s3_versioning_enabled              = var.s3_versioning_enabled
  splunk_endpoint                    = var.splunk_endpoint
  splunk_secrets_manager_secret_arn  = var.splunk_secrets_manager_secret_arn
  splunk_secrets_manager_kms_key_arn = var.splunk_secrets_manager_kms_key_arn
  tags                               = local.source_tags
  destination_type                   = "splunk"
}

resource "aws_iam_role" "cloudwatch_logs_to_firehose" {
  name        = local.cloudwatch_role_name
  description = "Allows CloudWatch Logs ${var.source_id} to publish to Firehose"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = local.cloudwatch_logs_principal
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "${local.source_log_group_arn}:*"
          }
        }
      },
    ]
  })

  tags = local.source_tags

  lifecycle {
    precondition {
      condition     = split(":", var.splunk_secrets_manager_secret_arn)[3] == data.aws_region.current.name
      error_message = "splunk_secrets_manager_secret_arn must be in the same AWS region as the Firehose stream."
    }

    precondition {
      condition     = var.splunk_secrets_manager_kms_key_arn == null || split(":", var.splunk_secrets_manager_kms_key_arn)[3] == data.aws_region.current.name
      error_message = "splunk_secrets_manager_kms_key_arn must be in the same AWS region as the Firehose stream."
    }
  }
}

resource "aws_iam_role_policy" "cloudwatch_logs_to_firehose" {
  name = local.cloudwatch_role_name
  role = aws_iam_role.cloudwatch_logs_to_firehose.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "firehose:PutRecord",
        ]
        Resource = [
          module.firehose.log_destination,
        ]
      },
    ]
  })
}

resource "aws_cloudwatch_log_subscription_filter" "this" {
  name            = local.subscription_filter_name
  role_arn        = aws_iam_role.cloudwatch_logs_to_firehose.arn
  log_group_name  = var.cloudwatch_log_group_name
  filter_pattern  = var.filter_pattern
  destination_arn = module.firehose.log_destination

  depends_on = [aws_iam_role_policy.cloudwatch_logs_to_firehose]
}
