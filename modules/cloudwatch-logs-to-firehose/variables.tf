variable "name" {
  description = "Lowercase name used for the Firehose stream, backup bucket, IAM resources, and monitoring resources."
  type        = string

  validation {
    condition     = length(var.name) >= 3 && length(var.name) <= 50 && can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.name))
    error_message = "name must be 3-50 lowercase alphanumeric or hyphen characters and start and end with an alphanumeric character."
  }
}

variable "cloudwatch_log_group_name" {
  description = "Existing CloudWatch log group to subscribe to this Firehose stream. Use one module instance per independently identifiable log source."
  type        = string

  validation {
    condition     = length(var.cloudwatch_log_group_name) > 0 && length(var.cloudwatch_log_group_name) <= 512
    error_message = "cloudwatch_log_group_name must be between 1 and 512 characters."
  }
}

variable "subscription_filter_name" {
  description = "Optional CloudWatch Logs subscription filter name. Defaults to <name>-to-firehose."
  type        = string
  default     = null
  nullable    = true
}

variable "filter_pattern" {
  description = "CloudWatch Logs filter pattern. The empty default forwards every event from the source log group."
  type        = string
  default     = ""
}

variable "source_id" {
  description = "Stable, non-secret identifier for the source, for example aws:rds:us-east-1:123456789012:db:image-builder-prod/postgresql. Configure the Splunk HEC token with this value as its default source."
  type        = string

  validation {
    condition     = length(var.source_id) > 0 && length(var.source_id) <= 256
    error_message = "source_id must be between 1 and 256 characters."
  }
}

variable "service_name" {
  description = "Service producing the logs, for example image-builder. Used for AWS resource tags and the source identity contract."
  type        = string

  validation {
    condition     = length(var.service_name) > 0 && length(var.service_name) <= 256
    error_message = "service_name must be between 1 and 256 characters."
  }
}

variable "environment" {
  description = "Environment producing the logs, for example stage or production. Used for AWS resource tags and the source identity contract."
  type        = string

  validation {
    condition     = length(var.environment) > 0 && length(var.environment) <= 256
    error_message = "environment must be between 1 and 256 characters."
  }
}

variable "splunk_endpoint" {
  description = "Splunk HEC endpoint URL."
  type        = string

  validation {
    condition     = can(regex("^https://[^[:space:]]+$", var.splunk_endpoint))
    error_message = "splunk_endpoint must be an HTTPS URL."
  }
}

variable "splunk_secrets_manager_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret containing the Splunk HEC token. The token is retrieved by Firehose and is not stored in Terraform state."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:secretsmanager:[^:]+:[0-9]{12}:secret:.+$", var.splunk_secrets_manager_secret_arn))
    error_message = "splunk_secrets_manager_secret_arn must be an AWS Secrets Manager secret ARN."
  }
}

variable "splunk_secrets_manager_kms_key_arn" {
  description = "Optional customer-managed KMS key ARN used to encrypt the Splunk HEC secret."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.splunk_secrets_manager_kms_key_arn == null || can(regex("^arn:[^:]+:kms:[^:]+:[0-9]{12}:key/.+$", var.splunk_secrets_manager_kms_key_arn))
    error_message = "splunk_secrets_manager_kms_key_arn must be a KMS key ARN when set."
  }
}

variable "splunk_index" {
  description = "Splunk index that the HEC token is restricted to. This module exposes the value as a contract; the Splunk team configures the token."
  type        = string

  validation {
    condition     = length(var.splunk_index) > 0 && length(var.splunk_index) <= 256
    error_message = "splunk_index must be between 1 and 256 characters."
  }
}

variable "splunk_sourcetype" {
  description = "Default Splunk sourcetype configured on the HEC token."
  type        = string
  default     = "aws:rds:postgresql"

  validation {
    condition     = length(var.splunk_sourcetype) > 0 && length(var.splunk_sourcetype) <= 256
    error_message = "splunk_sourcetype must be between 1 and 256 characters."
  }
}

variable "splunk_host" {
  description = "Default Splunk host configured on the HEC token, normally the RDS instance identifier."
  type        = string

  validation {
    condition     = length(var.splunk_host) > 0 && length(var.splunk_host) <= 256
    error_message = "splunk_host must be between 1 and 256 characters."
  }
}

variable "cloudwatch_log_retention" {
  description = "Retention in days for Firehose delivery error logs."
  type        = number
  default     = 30
}

variable "firehose_splunk_retry_duration" {
  description = "Duration in seconds that Firehose retries Splunk delivery."
  type        = number
  default     = 300

  validation {
    condition     = var.firehose_splunk_retry_duration >= 0 && var.firehose_splunk_retry_duration <= 7200
    error_message = "firehose_splunk_retry_duration must be between 0 and 7200 seconds."
  }
}

variable "hec_acknowledgment_timeout" {
  description = "Seconds Firehose waits for a Splunk HEC acknowledgment."
  type        = number
  default     = 300

  validation {
    condition     = var.hec_acknowledgment_timeout >= 180 && var.hec_acknowledgment_timeout <= 600
    error_message = "hec_acknowledgment_timeout must be between 180 and 600 seconds."
  }
}

variable "kinesis_firehose_buffer" {
  description = "S3 backup buffering size in MiB."
  type        = number
  default     = 10
}

variable "kinesis_firehose_buffer_interval" {
  description = "S3 backup buffering interval in seconds."
  type        = number
  default     = 400
}

variable "log_group_tags" {
  description = "Additional tags for the Firehose delivery error log group."
  type        = map(string)
  default     = {}
}

variable "log_stream_name" {
  description = "Firehose delivery error log stream name."
  type        = string
  default     = "SplunkDelivery"
}

variable "splunk_s3_backup_mode" {
  description = "Splunk backup mode: FailedEventsOnly or AllEvents."
  type        = string
  default     = "FailedEventsOnly"

  validation {
    condition     = contains(["FailedEventsOnly", "AllEvents"], var.splunk_s3_backup_mode)
    error_message = "splunk_s3_backup_mode must be FailedEventsOnly or AllEvents."
  }
}

variable "s3_compression_format" {
  description = "Compression format for records written to the backup bucket."
  type        = string
  default     = "GZIP"
}

variable "s3_prefix" {
  description = "Prefix for records written to the backup bucket."
  type        = string
  default     = "cloudwatch-logs/"
}

variable "s3_lifecycle_expiration_days" {
  description = "Days after which backup bucket objects expire."
  type        = number
  default     = 90

  validation {
    condition     = var.s3_lifecycle_expiration_days > 0 && floor(var.s3_lifecycle_expiration_days) == var.s3_lifecycle_expiration_days
    error_message = "s3_lifecycle_expiration_days must be a positive whole number of days."
  }
}

variable "s3_versioning_enabled" {
  description = "Whether object versioning is enabled on the Firehose backup bucket."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags for resources created by this module. Environment, LogSource, and Service are reserved and set from explicit inputs."
  type        = map(string)
  default     = {}
}
