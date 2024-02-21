locals {
  name = length(var.vpc_name) > 0 ? var.vpc_name : var.vpc_id

}

resource "aws_flow_log" "vpc" {
  log_destination          = aws_kinesis_firehose_delivery_stream.vpc_logs_to_splunk.arn
  log_destination_type     = "kinesis-data-firehose"
  traffic_type             = "ALL"
  vpc_id                   = var.vpc_id
  max_aggregation_interval = var.flow_log_max_aggregation_interval
  log_format               = var.log_format
}

# Endpoint type is set to Raw
# See https://aws.amazon.com/blogs/big-data/ingest-vpc-flow-logs-into-splunk-using-amazon-kinesis-data-firehose/
resource "aws_kinesis_firehose_delivery_stream" "vpc_logs_to_splunk" {
  name        = "${local.name}-vpc-logs-to-splunk"
  destination = "splunk"

  splunk_configuration {
    hec_endpoint               = var.splunk_endpoint
    hec_token                  = var.hec_token
    hec_acknowledgment_timeout = var.hec_acknowledgment_timeout
    hec_endpoint_type          = "Raw"
    retry_duration             = var.firehose_splunk_retry_duration
    s3_backup_mode             = var.s3_backup_mode

    s3_configuration {
      role_arn           = aws_iam_role.kinesis_firehose.arn
      bucket_arn         = aws_s3_bucket.kinesis_firehose.arn
      prefix             = var.s3_prefix
      buffering_size     = var.kinesis_firehose_buffer
      buffering_interval = var.kinesis_firehose_buffer_interval
      compression_format = var.s3_compression_format
    }

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.kinesis.name
      log_stream_name = aws_cloudwatch_log_stream.kinesis.name
    }
  }

  tags = merge(
    {
      Name               = "${local.name}-vpc-logs-to-splunk"
      LogDeliveryEnabled = "true"
    },
    var.tags,
  )
}

resource "aws_s3_bucket" "kinesis_firehose" {
  bucket = "${local.name}-flow-logs"
  tags = merge(
    { Name = "${local.name}-flow-logs" },
    var.tags,
  )
}

resource "aws_s3_bucket_ownership_controls" "kinesis_firehose" {
  bucket = aws_s3_bucket.kinesis_firehose.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "kinesis_firehose" {
  bucket     = aws_s3_bucket.kinesis_firehose.id
  acl        = "private"
  depends_on = [aws_s3_bucket_ownership_controls.kinesis_firehose]
}

resource "aws_cloudwatch_log_group" "kinesis" {
  name              = "/aws/kinesisfirehose/${local.name}-vpc-logs-to-splunk"
  retention_in_days = var.cloudwatch_log_retention

  tags = merge(
    var.tags,
    var.log_group_tags,
  )
}

resource "aws_cloudwatch_log_stream" "kinesis" {
  name           = var.log_stream_name
  log_group_name = aws_cloudwatch_log_group.kinesis.name
}

resource "aws_iam_role" "kinesis_firehose" {
  name        = "${local.name}-vpc-flow-logs-to-splunk-kinesis-firehose"
  description = "IAM Role for Kinesis Firehose to send ${local.name} vpc flow logs to splunk"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      },
    ]
  })

  inline_policy {
    name = "${local.name}-vpc-flow-logs-to-splunk-kinesis-firehose"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow",
          Action = [
            "s3:AbortMultipartUpload",
            "s3:GetBucketLocation",
            "s3:GetObject",
            "s3:ListBucket",
            "s3:ListBucketMultipartUploads",
            "s3:PutObject",
          ],
          Resource = [
            aws_s3_bucket.kinesis_firehose.arn,
            "${aws_s3_bucket.kinesis_firehose.arn}/*",
          ]
        },
      ]
    })
  }

  tags = merge(
    { Name = "${local.name}-vpc-flow-logs-to-splunk-kinesis-firehose" },
    var.tags,
  )
}
