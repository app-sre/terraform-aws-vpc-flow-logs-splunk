variable "cloudwatch_log_retention" {}

variable "firehose_splunk_retry_duration" {}

variable "hec_acknowledgment_timeout" {}

variable "hec_token" {}

variable "kinesis_firehose_buffer" {}

variable "kinesis_firehose_buffer_interval" {}

variable "log_group_tags" {}

variable "log_stream_name" {}

variable "s3_backup_mode" {}

variable "s3_compression_format" {}

variable "s3_prefix" {}

variable "splunk_endpoint" {}

variable "tags" {}

variable "flow_log_max_aggregation_interval" {
  description = "The maximum interval of time (60 or 600 s) during which a flow of packets is captured and aggregated into a flow log record. Select the minimum setting of 60s interval if you need the flow log data to be available for near-real-time analysis in Splunk."
  type        = number
  default     = 600
}

variable "log_format" {
  description = "(Optional) The fields to include in the flow log record."
  type        = string
  default     = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status}"
}

# vpc_name limited to the length of a vpc id, as it will be used if name not provided.
variable "vpc_name" {
  description = "Name of the vpc that we will send the flow logs to Splunk. It will be used in names, descriptions, etc... vpc_id will be used instead if not defined."
  type        = string
  default     = ""

  validation {
    condition     = length(var.vpc_name) <= 21
    error_message = "The vpc_name cannot be longer than 21 characters."
  }
}

variable "vpc_id" {
  description = "VPC id"
  type        = string

  validation {
    condition     = length(var.vpc_id) <= 21
    error_message = "The vpc_id cannot be longer than 21 characters."
  }
}
