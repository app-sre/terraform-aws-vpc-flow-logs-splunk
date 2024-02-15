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

variable "flow_log_max_aggregation_interval" {
  description = "The maximum interval of time (60 or 600 s) during which a flow of packets is captured and aggregated into a flow log record. Select the minimum setting of 60s interval if you need the flow log data to be available for near-real-time analysis in Splunk."
  type        = number
  default     = 600
}

variable "hec_acknowledgment_timeout" {
  description = "The amount of time, in seconds between 180 and 600, that Kinesis Firehose waits to receive an acknowledgment from Splunk after it sends it data."
  type        = string
  default     = 300
}

variable "hec_token" {
  description = "KMS encoded Splunk hec token"
  type        = string
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

variable "lambda_function_timeout" {
  description = "The function execution time at which Lambda should terminate the function."
  type        = number
  default     = 180
}

variable "lambda_processing_buffer_interval_in_seconds" {
  description = "Lambda processing buffer interval in seconds."
  type        = number
  default     = 61 # If 60 is the default, it is not stored in state and there are perpetual changes in the plan
}

variable "lambda_processing_buffer_size_in_mb" {
  description = "Lambda processing buffer size in mb."
  type        = number
  default     = 0.256
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

variable "vpc_name" {
  description = "Name of the vpc that we will send the flow logs to Splunk. It will be used in names, descriptions, etc..."
  type        = string
}

variable "vpc_id" {
  description = "VPC id"
  type        = string
}
