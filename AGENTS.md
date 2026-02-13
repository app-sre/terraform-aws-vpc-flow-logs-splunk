# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## Build and Validation Commands

```bash
terraform fmt -check    # Check formatting (CI enforced)
terraform fmt           # Auto-format files
terraform init          # Initialize providers
terraform validate      # Validate configuration
```

## Architecture

This Terraform module forwards VPC Flow Logs to Splunk via AWS Kinesis Firehose (no Lambda required).

### Module Structure

- **Root module** (`main.tf`): Creates `aws_flow_log` resource and invokes the firehose submodule
- **`modules/splunk-firehose-connection/`**: Reusable submodule that sets up:
  - Kinesis Firehose delivery stream with Splunk destination (Raw endpoint type)
  - S3 bucket for failed event backup
  - CloudWatch log group/stream for delivery monitoring
  - IAM role with S3 permissions for Firehose

### Data Flow

VPC Flow Logs -> Kinesis Firehose -> Splunk HEC (Raw endpoint)
                      |
                      v
              S3 (failed events only, by default)

### Requirements

- Terraform >= 1.0
- AWS Provider >= 5.0.0
- Splunk AWS Add-on >= 7.3.0

