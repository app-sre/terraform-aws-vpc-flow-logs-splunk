variable "cloudwatch_log_group_prefix" {
  description = "Cloudwatch log group name prefix, e.g. /aws/kinesisfirehose"
  type        = string
}

variable "cloudwatch_log_retention" {
  description = "Length in days to keep CloudWatch logs of Kinesis Firehose."
  type        = number
  default     = 30
}

variable "firehose_splunk_retry_duration" {
  description = "Firehose delivery retry duration (between 0 and 7200)."
  type        = number
  default     = 300
}

variable "hec_acknowledgment_timeout" {
  description = "The amount of time, in seconds between 180 and 600, that Kinesis Firehose waits to receive an acknowledgment from Splunk after it sends it data."
  type        = string
  default     = 300
}

variable "hec_token" {
  description = "Splunk HEC token. Prefer splunk_secrets_manager_secret_arn for new deployments so the token is not stored in Terraform state. Exactly one credential source must be set for a Splunk destination."
  type        = string
  sensitive   = true
  default     = null
  nullable    = true
}

variable "splunk_secrets_manager_secret_arn" {
  description = "ARN of an AWS Secrets Manager secret containing the Splunk HEC token. Exactly one of this variable or hec_token must be set for a Splunk destination."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.splunk_secrets_manager_secret_arn == null || can(regex("^arn:[^:]+:secretsmanager:[^:]+:[0-9]{12}:secret:.+$", var.splunk_secrets_manager_secret_arn))
    error_message = "splunk_secrets_manager_secret_arn must be a Secrets Manager secret ARN when set."
  }
}

variable "splunk_secrets_manager_kms_key_arn" {
  description = "Optional customer-managed KMS key ARN used to encrypt the Splunk HEC secret. When set, the Firehose role receives kms:Decrypt for this key."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.splunk_secrets_manager_kms_key_arn == null || can(regex("^arn:[^:]+:kms:[^:]+:[0-9]{12}:key/.+$", var.splunk_secrets_manager_kms_key_arn))
    error_message = "splunk_secrets_manager_kms_key_arn must be a KMS key ARN when set."
  }
}

variable "cloudwatch_logs_source" {
  description = "Whether Firehose receives gzip-compressed CloudWatch Logs subscription records. Enables decompression and message extraction for the Splunk destination."
  type        = bool
  default     = false
}

variable "kinesis_firehose_buffer" {
  description = "Buffer incoming data to the specified size, in MBs between 1 to 100, before delivering it to the destination."
  type        = number
  default     = 10
}

variable "kinesis_firehose_buffer_interval" {
  description = "Buffer incoming data for the specified period of time, in seconds between 0 to 900, before delivering it to the destination."
  type        = number
  default     = 400
}

variable "log_group_tags" {
  description = "A map of additional tags to add to all cloudwatch log groups"
  type        = map(string)
  default     = {}
}

variable "log_stream_name" {
  description = "Name of the CloudWatch log stream for Kinesis Firehose CloudWatch log group"
  type        = string
  default     = "SplunkDelivery"
}

variable "name" {
  description = "Name used for related objects in AWS"
  type        = string
}

variable "splunk_s3_backup_mode" {
  description = "S3 backup mode for Splunk destination: FailedEventsOnly or AllEvents"
  type        = string
  default     = "FailedEventsOnly"
}

variable "http_endpoint_s3_backup_mode" {
  description = "S3 backup mode for HTTP endpoint destination: FailedDataOnly or AllData"
  type        = string
  default     = "FailedDataOnly"
}
variable "s3_compression_format" {
  description = "The compression format for what the Kinesis Firehose puts in the s3 bucket"
  type        = string
  default     = "GZIP"
}

variable "s3_prefix" {
  description = "Prefix for the kinesis firehose related bucket."
  type        = string
  default     = "kinesis-firehose/"
}

variable "s3_bucket_name" {
  description = "Optional globally unique name for the Firehose backup bucket. Defaults to name for backward compatibility."
  type        = string
  default     = null
  nullable    = true
}

variable "s3_lifecycle_expiration_days" {
  description = "Number of days after which objects in the Kinesis Firehose backup S3 bucket expire. If s3_versioning_enabled is true, the underlying data is fully removed shortly after this many days rather than exactly on it."
  type        = number
  default     = 90

  validation {
    condition     = var.s3_lifecycle_expiration_days > 0 && floor(var.s3_lifecycle_expiration_days) == var.s3_lifecycle_expiration_days
    error_message = "s3_lifecycle_expiration_days must be a positive whole number of days."
  }
}

variable "s3_versioning_enabled" {
  description = "Whether to enable object versioning on the Kinesis Firehose backup S3 bucket. Not needed by Firehose itself - it exists to satisfy policy-as-code guardrails (e.g. Conftest against policies/s3.rego) that require versioning on every S3 bucket. Defaults to true so the module passes those guardrails out of the box; set to false to opt out."
  type        = bool
  default     = true
}

variable "splunk_endpoint" {
  description = "Splunk endpoint URL."
  type        = string
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

variable "destination_type" {
  description = "Firehose destination type: splunk or http_endpoint"
  type        = string
  default     = "splunk"

  validation {
    condition     = contains(["splunk", "http_endpoint"], var.destination_type)
    error_message = "destination_type must be 'splunk' or 'http_endpoint'"
  }
}

variable "http_endpoint_name" {
  description = "HTTP endpoint name"
  type        = string
  default     = "Splunk HTTP Endpoint"
}

variable "http_endpoint_retry_duration" {
  description = "Total time in seconds for retries (0-7200)"
  type        = number
  default     = 300
}

variable "http_endpoint_content_encoding" {
  description = "Content encoding: GZIP or NONE"
  type        = string
  default     = "GZIP"
}

variable "http_endpoint_common_attributes" {
  description = "List of common attributes (name/value pairs) sent with each request"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}
