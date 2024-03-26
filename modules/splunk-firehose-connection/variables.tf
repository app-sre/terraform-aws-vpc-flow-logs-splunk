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
  description = "Pass the HEC token in plain text (not recommended) or through a parameter store, through a KMS encryption module, etc..."
  type        = string
  sensitive   = true
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

variable "s3_backup_mode" {
  description = "Defines how documents should be delivered to Amazon S3."
  type        = string
  default     = "FailedEventsOnly"
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

variable "splunk_endpoint" {
  description = "Splunk endpoint"
  type        = string
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
