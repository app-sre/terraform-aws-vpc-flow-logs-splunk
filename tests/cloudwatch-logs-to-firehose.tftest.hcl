mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:user/terraform-test"
      id         = "123456789012"
      user_id    = "AIDATEST"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      dns_suffix = "amazonaws.com"
      partition  = "aws"
    }
  }

  mock_data "aws_region" {
    defaults = {
      name = "us-east-1"
    }
  }

  mock_resource "aws_kinesis_firehose_delivery_stream" {
    override_during = plan

    defaults = {
      arn  = "arn:aws:firehose:us-east-1:123456789012:deliverystream/image-builder-prod-db-logs"
      name = "image-builder-prod-db-logs"
    }
  }

  mock_resource "aws_s3_bucket" {
    override_during = plan

    defaults = {
      arn = "arn:aws:s3:::image-builder-prod-db-logs-123456789012"
      id  = "image-builder-prod-db-logs-123456789012"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    override_during = plan

    defaults = {
      arn  = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/kinesisfirehose/image-builder-prod-db-logs"
      name = "/aws/kinesisfirehose/image-builder-prod-db-logs"
    }
  }

  mock_resource "aws_cloudwatch_log_stream" {
    override_during = plan

    defaults = {
      name = "SplunkDelivery"
    }
  }
}

run "plans_single_source_cloudwatch_pipeline" {
  command = plan

  module {
    source = "./modules/cloudwatch-logs-to-firehose"
  }

  variables {
    name                              = "image-builder-prod-db-logs"
    cloudwatch_log_group_name         = "/aws/rds/instance/image-builder-prod/postgresql"
    source_id                         = "aws:rds:us-east-1:123456789012:db:image-builder-prod/postgresql"
    service_name                      = "image-builder"
    environment                       = "production"
    splunk_endpoint                   = "https://splunk.example.test:8088"
    splunk_secrets_manager_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:image-builder-splunk-hec-AbCdEf"
    splunk_index                      = "app-sre-security"
    splunk_host                       = "image-builder-prod"
  }

  assert {
    condition     = aws_cloudwatch_log_subscription_filter.this.log_group_name == "/aws/rds/instance/image-builder-prod/postgresql"
    error_message = "The subscription filter must target the configured log group."
  }

  assert {
    condition     = aws_cloudwatch_log_subscription_filter.this.destination_arn == output.delivery_stream_arn
    error_message = "The subscription filter must target the module's Firehose stream."
  }

  assert {
    condition     = jsondecode(aws_iam_role.cloudwatch_logs_to_firehose.assume_role_policy).Statement[0].Principal.Service == "logs.amazonaws.com"
    error_message = "The delivery role must trust the CloudWatch Logs service principal."
  }

  assert {
    condition     = jsondecode(aws_iam_role.cloudwatch_logs_to_firehose.assume_role_policy).Statement[0].Condition.ArnLike["aws:SourceArn"] == "arn:aws:logs:us-east-1:123456789012:log-group:/aws/rds/instance/image-builder-prod/postgresql:*"
    error_message = "The delivery role trust must be scoped to the configured source log group."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.cloudwatch_logs_to_firehose.policy).Statement[0].Action == ["firehose:PutRecord"]
    error_message = "The CloudWatch Logs role must have only the documented Firehose PutRecord permission."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.cloudwatch_logs_to_firehose.policy).Statement[0].Resource == [output.delivery_stream_arn]
    error_message = "The CloudWatch Logs role must be scoped to the selected Firehose stream."
  }

  assert {
    condition = output.required_splunk_hec_metadata == {
      host       = "image-builder-prod"
      index      = "app-sre-security"
      source     = "aws:rds:us-east-1:123456789012:db:image-builder-prod/postgresql"
      sourcetype = "aws:rds:postgresql"
    }
    error_message = "The module must expose the exact Splunk source identity contract."
  }
}

run "enables_cloudwatch_decompression_and_message_extraction" {
  command = plan

  module {
    source = "./modules/splunk-firehose-connection"
  }

  variables {
    name                              = "image-builder-prod-db-logs"
    cloudwatch_log_group_prefix       = "/aws/kinesisfirehose"
    cloudwatch_logs_source            = true
    splunk_endpoint                   = "https://splunk.example.test:8088"
    splunk_secrets_manager_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:image-builder-splunk-hec-AbCdEf"
  }

  assert {
    condition     = length(aws_kinesis_firehose_delivery_stream.logs_to_splunk[0].splunk_configuration[0].processing_configuration[0].processors) == 2
    error_message = "CloudWatch Logs delivery must configure decompression and message extraction processors."
  }

  assert {
    condition     = contains([for processor in aws_kinesis_firehose_delivery_stream.logs_to_splunk[0].splunk_configuration[0].processing_configuration[0].processors : processor.type], "Decompression")
    error_message = "CloudWatch Logs delivery must enable Firehose decompression."
  }

  assert {
    condition     = contains([for processor in aws_kinesis_firehose_delivery_stream.logs_to_splunk[0].splunk_configuration[0].processing_configuration[0].processors : processor.type], "CloudWatchLogProcessing")
    error_message = "CloudWatch Logs delivery must enable Firehose message extraction."
  }

  assert {
    condition     = anytrue([for statement in jsondecode(aws_iam_role_policy.kinesis_firehose.policy).Statement : contains(try(statement.Action, []), "secretsmanager:GetSecretValue") && contains(try(statement.Resource, []), "arn:aws:secretsmanager:us-east-1:123456789012:secret:image-builder-splunk-hec-AbCdEf")])
    error_message = "The Firehose role must retrieve only the configured Splunk HEC secret."
  }

  assert {
    condition     = anytrue([for statement in jsondecode(aws_iam_role_policy.kinesis_firehose.policy).Statement : contains(try(statement.Action, []), "logs:PutLogEvents")])
    error_message = "The Firehose role must be able to write its delivery error log stream."
  }
}

run "rejects_ambiguous_splunk_credentials" {
  command = plan

  module {
    source = "./modules/splunk-firehose-connection"
  }

  variables {
    name                              = "image-builder-prod-db-logs"
    cloudwatch_log_group_prefix       = "/aws/kinesisfirehose"
    splunk_endpoint                   = "https://splunk.example.test:8088"
    hec_token                         = "not-a-real-token"
    splunk_secrets_manager_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:image-builder-splunk-hec-AbCdEf"
  }

  expect_failures = [
    aws_kinesis_firehose_delivery_stream.logs_to_splunk[0],
  ]
}

run "preserves_direct_firehose_defaults" {
  command = plan

  module {
    source = "./modules/splunk-firehose-connection"
  }

  variables {
    name                        = "existing-vpc-flow-logs"
    cloudwatch_log_group_prefix = "/aws/kinesisfirehose"
    splunk_endpoint             = "https://splunk.example.test:8088"
    hec_token                   = "not-a-real-token"
  }

  assert {
    condition     = length(aws_kinesis_firehose_delivery_stream.logs_to_splunk[0].splunk_configuration[0].processing_configuration) == 0
    error_message = "Existing direct Firehose producers must not receive CloudWatch Logs processors."
  }

  assert {
    condition     = length(aws_kinesis_firehose_delivery_stream.logs_to_splunk[0].splunk_configuration[0].secrets_manager_configuration) == 0
    error_message = "Existing direct Firehose producers must continue to support the legacy HEC token input."
  }
}

run "rejects_unimplemented_cloudwatch_http_destination" {
  command = plan

  module {
    source = "./modules/splunk-firehose-connection"
  }

  variables {
    name                        = "future-sumo-logs"
    cloudwatch_log_group_prefix = "/aws/kinesisfirehose"
    cloudwatch_logs_source      = true
    destination_type            = "http_endpoint"
    splunk_endpoint             = "https://sumo.example.test/receiver/v1/http/example"
    hec_token                   = "not-a-real-token"
  }

  expect_failures = [
    aws_kinesis_firehose_delivery_stream.logs_to_http_endpoint[0],
  ]
}

run "rejects_cross_region_splunk_secret" {
  command = plan

  module {
    source = "./modules/splunk-firehose-connection"
  }

  variables {
    name                              = "cross-region-secret"
    cloudwatch_log_group_prefix       = "/aws/kinesisfirehose"
    splunk_endpoint                   = "https://splunk.example.test:8088"
    splunk_secrets_manager_secret_arn = "arn:aws:secretsmanager:us-west-2:123456789012:secret:splunk-hec-AbCdEf"
  }

  expect_failures = [
    aws_kinesis_firehose_delivery_stream.logs_to_splunk[0],
  ]
}
