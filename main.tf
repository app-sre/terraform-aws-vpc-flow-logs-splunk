resource "aws_flow_log" "vpc" {
  log_destination          = aws_kinesis_firehose_delivery_stream.vpc_logs_to_splunk.arn
  log_destination_type     = "kinesis-data-firehose"
  traffic_type             = "ALL"
  vpc_id                   = var.vpc_id
  max_aggregation_interval = var.flow_log_max_aggregation_interval
}

# endpoint type is set to Raw since we're using the Splunk provider lambda to send data.
# See https://aws.amazon.com/blogs/big-data/ingest-vpc-flow-logs-into-splunk-using-amazon-kinesis-data-firehose/
resource "aws_kinesis_firehose_delivery_stream" "vpc_logs_to_splunk" {
  name        = "${var.vpc_name}-vpc-logs-to-splunk"
  destination = "splunk"

  splunk_configuration {
    hec_endpoint               = var.splunk_endpoint
    hec_token                  = module.hec_token_kms_secret.hec_token_kms_secret
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

    processing_configuration {
      enabled = true

      processors {
        type = "Lambda"

        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = "${aws_lambda_function.splunk_firehose_flowlogs_processor.arn}:$LATEST"
        }

        parameters {
          parameter_name  = "RoleArn"
          parameter_value = aws_iam_role.kinesis_firehose.arn
        }

        parameters {
          parameter_name  = "BufferSizeInMBs"
          parameter_value = var.lambda_processing_buffer_size_in_mb
        }

        parameters {
          parameter_name  = "BufferIntervalInSeconds"
          parameter_value = var.lambda_processing_buffer_interval_in_seconds
        }
      }
    }

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.kinesis.name
      log_stream_name = aws_cloudwatch_log_stream.kinesis.name
    }
  }

  tags = merge(
    {
      Name               = "${var.vpc_name}-vpc-logs-to-splunk"
      LogDeliveryEnabled = "true"
    },
    var.tags,
  )
}

resource "aws_s3_bucket" "kinesis_firehose" {
  bucket = "${var.vpc_name}-flow-logs"
  tags = merge(
    { Name = "${var.vpc_name}-flow-logs" },
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

module "hec_token_kms_secret" {
  source    = "disney/kinesis-firehose-splunk/aws//modules/kms_secrets"
  hec_token = var.hec_token
  version   = "8.1.0" # this cannot be set in a variable, see https://github.com/hashicorp/terraform/issues/28912
}

resource "aws_cloudwatch_log_group" "kinesis" {
  name              = "/aws/kinesisfirehose/${var.vpc_name}-vpc-logs-to-splunk"
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

resource "aws_iam_role" "vpc_flow_logs_to_splunk_kinesis_firehose_lambda" {
  name        = "${var.vpc_name}-vpc-flow-logs-to-splunk-kinesis-firehose-lambda"
  description = "Role for Lambda function to transform VPC Flow Logs into Splunk compatible format"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })

  inline_policy {
    name = "${var.vpc_name}-vpc-flow-logs-to-splunk-kinesis-firehose-lambda"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow",
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ],
          Resource = ["*"]
        },
      ]
    })
  }

  tags = merge(
    { Name = "${var.vpc_name}-vpc-flow-logs-to-splunk-kinesis-firehose-lambda" },
    var.tags,
  )
}

# Prepare Lambda package (https://github.com/hashicorp/terraform/issues/8344#issuecomment-345807204)
resource "null_resource" "pip" {
  triggers = {
    app          = "${base64sha256(file("${path.module}/splunk-aws-firehose-flowlogs-processor/SplunkFirehoseFlowlogsProcessor/app.py"))}"
    requirements = "${base64sha256(file("${path.module}/splunk-aws-firehose-flowlogs-processor/SplunkFirehoseFlowlogsProcessor/requirements.txt"))}"
  }

  provisioner "local-exec" {
    command = "pip install --no-compile --no-cache-dir -r ${path.module}/splunk-aws-firehose-flowlogs-processor/SplunkFirehoseFlowlogsProcessor/requirements.txt -t ${path.module}/splunk-aws-firehose-flowlogs-processor/SplunkFirehoseFlowlogsProcessor/lib"
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/splunk-aws-firehose-flowlogs-processor/SplunkFirehoseFlowlogsProcessor/"
  output_path = "${path.module}/splunk-aws-firehose-flowlogs-processor/SplunkFirehoseFlowlogsProcessor.zip"
  depends_on  = [null_resource.pip]
}

resource "aws_lambda_function" "splunk_firehose_flowlogs_processor" {
  filename         = "${path.module}/splunk-aws-firehose-flowlogs-processor/SplunkFirehoseFlowlogsProcessor.zip"
  function_name    = "splunk-firehose-flowlogs-processor"
  role             = aws_iam_role.vpc_flow_logs_to_splunk_kinesis_firehose_lambda.arn
  handler          = "app.lambda_handler"
  runtime          = "python3.8"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = var.lambda_function_timeout

  tags = merge(
    { Name = "splunk-firehose-flowlogs-processor" },
    var.tags,
  )
}

resource "aws_iam_role" "kinesis_firehose" {
  name        = "${var.vpc_name}-vpc-flow-logs-to-splunk-kinesis-firehose"
  description = "IAM Role for Kinesis Firehose to send ${var.vpc_name} vpc flow logs to splunk"

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
    name = "${var.vpc_name}-vpc-flow-logs-to-splunk-kinesis-firehose"

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
        {
          Effect = "Allow",
          Action = [
            "lambda:InvokeFunction",
            "lambda:GetFunctionConfiguration",
          ],
          Resource = [
            "${aws_lambda_function.splunk_firehose_flowlogs_processor.arn}:$LATEST"
          ]
        },
      ]
    })
  }

  tags = merge(
    { Name = "${var.vpc_name}-vpc-flow-logs-to-splunk-kinesis-firehose" },
    var.tags,
  )
}
