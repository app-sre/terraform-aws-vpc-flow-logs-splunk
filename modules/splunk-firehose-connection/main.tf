# Endpoint type is set to Raw
# See https://aws.amazon.com/blogs/big-data/ingest-vpc-flow-logs-into-splunk-using-amazon-kinesis-data-firehose/
resource "aws_kinesis_firehose_delivery_stream" "logs_to_splunk" {
  count       = var.destination_type == "splunk" ? 1 : 0
  name        = var.name
  destination = "splunk"

  splunk_configuration {
    hec_endpoint               = var.splunk_endpoint
    hec_token                  = var.hec_token
    hec_acknowledgment_timeout = var.hec_acknowledgment_timeout
    hec_endpoint_type          = "Raw"
    retry_duration             = var.firehose_splunk_retry_duration
    s3_backup_mode             = var.splunk_s3_backup_mode

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
      Name               = var.name
      LogDeliveryEnabled = "true"
    },
    var.tags,
  )
}

resource "aws_kinesis_firehose_delivery_stream" "logs_to_http_endpoint" {
  count       = var.destination_type == "http_endpoint" ? 1 : 0
  name        = "${var.name}-via-http-endpoint"
  destination = "http_endpoint"

  http_endpoint_configuration {
    url                = var.splunk_endpoint
    name               = var.http_endpoint_name
    access_key         = var.hec_token
    s3_backup_mode     = var.http_endpoint_s3_backup_mode
    buffering_size     = var.kinesis_firehose_buffer
    buffering_interval = var.kinesis_firehose_buffer_interval
    retry_duration     = var.http_endpoint_retry_duration
    role_arn           = aws_iam_role.kinesis_firehose.arn

    request_configuration {
      content_encoding = var.http_endpoint_content_encoding

      dynamic "common_attributes" {
        for_each = var.http_endpoint_common_attributes
        content {
          name  = common_attributes.value.name
          value = common_attributes.value.value
        }
      }
    }

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
      Name               = var.name
      LogDeliveryEnabled = "true"
    },
    var.tags,
  )
}

resource "aws_s3_bucket" "kinesis_firehose" {
  bucket = var.name
  tags = merge(
    { Name = var.name },
    var.tags,
  )
}

resource "aws_s3_bucket_public_access_block" "kinesis_firehose" {
  bucket = aws_s3_bucket.kinesis_firehose.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "kinesis_firehose" {
  bucket = aws_s3_bucket.kinesis_firehose.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "kinesis_firehose" {
  bucket = aws_s3_bucket.kinesis_firehose.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "kinesis_firehose" {
  # Must be created after versioning is applied (AWS provider docs);
  # unrelated to this repo's "no depends_on in modules" convention.
  depends_on = [aws_s3_bucket_versioning.kinesis_firehose]

  bucket = aws_s3_bucket.kinesis_firehose.id

  rule {
    id     = "expire-old-backup-objects"
    status = "Enabled"

    filter {}

    expiration {
      days = var.s3_lifecycle_expiration_days
    }

    # Short, and deliberately NOT var.s3_lifecycle_expiration_days: on a
    # versioned bucket, the expiration above doesn't delete the object -
    # it adds a delete marker and demotes the object to a noncurrent
    # version. This purges the actual bytes shortly after, so real
    # retention stays close to s3_lifecycle_expiration_days instead of
    # roughly double it.
    noncurrent_version_expiration {
      noncurrent_days = 1
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # expiration.expired_object_delete_marker can't share a rule with
  # expiration.days (the AWS API rejects that combination), so the stray
  # delete marker left once the noncurrent version above is purged needs
  # its own rule to actually get cleaned up.
  rule {
    id     = "remove-expired-delete-markers"
    status = "Enabled"

    filter {}

    expiration {
      expired_object_delete_marker = true
    }
  }
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
  name              = "${var.cloudwatch_log_group_prefix}/${var.name}"
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
  name        = var.name
  description = "IAM Role for Kinesis Firehose for ${var.name}"

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

  tags = merge(
    { Name = var.name },
    var.tags,
  )
}

resource "aws_iam_role_policy" "kinesis_firehose" {
  name = var.name
  role = aws_iam_role.kinesis_firehose.id
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
