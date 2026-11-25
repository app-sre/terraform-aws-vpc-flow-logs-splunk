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

This repository provides Terraform modules that forward AWS logs to Splunk via Amazon Data Firehose (no Lambda required).

### Module Structure

- **Root module** (`main.tf`): Creates `aws_flow_log` resource and invokes the firehose submodule
- **`modules/splunk-firehose-connection/`**: Reusable submodule that sets up:
  - Kinesis Firehose delivery stream with Splunk destination (Raw endpoint type)
  - S3 bucket for failed event backup
  - CloudWatch log group/stream for delivery monitoring
  - IAM role with S3 permissions for Firehose
- **`modules/cloudwatch-logs-to-firehose/`**: Subscribes one existing CloudWatch log group to a dedicated Firehose stream with:
  - Least-privilege CloudWatch Logs delivery role
  - CloudWatch Logs decompression and message extraction
  - Secrets Manager-backed Splunk HEC authentication
  - Explicit source identity contract for Splunk HEC metadata

### Data Flow

VPC Flow Logs -> Kinesis Firehose -> Splunk HEC (Raw endpoint)
                      |
                      v
              S3 (failed events only, by default)

RDS -> CloudWatch Logs -> subscription filter -> Data Firehose -> Splunk HEC
                                                        |
                                                        v
                                                S3 (failed events)

### Requirements

- Terraform >= 1.2
- AWS Provider >= 5.59.0 and < 6.0.0
- Splunk AWS Add-on >= 7.3.0
