# Forward VPC Flow logs to Splunk via AWS Firehose

This module configures a Kinesis Firehose, sets up a subscription for a desired 
CloudWatch Log Group to the Firehose, and sends the log data to Splunk.

# Prerequisites

* Terraform >= 1.0.0
* [Splunk AWS Add-on][Splunk AWS Add-on URL] >= 7.3.0

[Splunk AWS Add-on URL]: https://docs.splunk.com/Documentation/AddOns/released/AWS

According to [AWS Big Data Blog][AWS Big Data Blog URL], a Lambda is no longer required 
to transform the VPC flow logs according to the 7.3.0 version in Splunk AWS Add-on, hence
this module does not contain any Lambda processing any more. 

If you need to send data to a Splunk system with an older Add-on, please take a look at 
v0.1.0 of this module.

[AWS Big Data Blog URL]: https://aws.amazon.com/blogs/big-data/ingest-vpc-flow-logs-into-splunk-using-amazon-kinesis-data-firehose

## Destination Types

This module supports two destination types for sending data to Splunk:

* **splunk** (default): Uses the native Splunk destination with HEC Raw endpoint
* **http_endpoint**: Uses the generic HTTP endpoint destination, useful when sending data through a proxy or load balancer

Both destination types use the same `splunk_endpoint` and `hec_token` variables.

## Security

The Kinesis Firehose backup S3 bucket (used for failed events / backup data, per `splunk_s3_backup_mode` / `http_endpoint_s3_backup_mode`) is hardened by default:

* **Public access blocked** — all four S3 public access block settings are enabled.
* **Versioned** — object versioning is always enabled.
* **Encrypted** — server-side encryption (SSE-S3 / `AES256`) is always enabled.
* **Lifecycle-managed** — objects expire after `s3_lifecycle_expiration_days` (default `90`); since the bucket is versioned, the underlying data is fully removed shortly after that rather than exactly on it. Incomplete multipart uploads are aborted after 7 days.

None of the above is optional — this bucket only ever holds log/backup data, so there's no supported way to disable these protections. Only the retention window (`s3_lifecycle_expiration_days`) is configurable.

**Upgrading an existing deployment:** the lifecycle rule applies by object age, not by when the rule was added — pre-existing objects already older than `s3_lifecycle_expiration_days` will be expired on the next daily lifecycle evaluation after upgrading. If you use `splunk_s3_backup_mode`/`http_endpoint_s3_backup_mode = AllEvents`/`AllData` and rely on this bucket as a long-term archive rather than just failed-event backup, review its contents before upgrading.

## Usage

* Example for handling multiple VPCs:
    ```
    data "aws_vpcs" "all_vpcs" {}

    locals {
      vpc_ids = toset(data.aws_vpcs.all_vpcs.ids)
    }

    module "vpc_flow_logs_to_splunk" {
      for_each        = { for vpc_id in local.vpc_ids : vpc_id => vpc_id }
      vpc_id          = each.key
      hec_token       = var.hec_token
      splunk_endpoint = "<your Splunk endpoint>"
      source          = "github.com/app-sre/terraform-aws-vpc-flow-logs-splunk?<x.y.z>"
    }
    ```

* Example using HTTP endpoint destination:
    ```
    module "vpc_flow_logs_to_splunk" {
      source           = "github.com/app-sre/terraform-aws-vpc-flow-logs-splunk?ref=v<x.y.z>"
      vpc_id           = "<your vpc_id>"
      hec_token        = var.hec_token
      splunk_endpoint  = "<your Splunk endpoint>"
      destination_type = "http_endpoint"
    }
    ```
**Notice:** Do *not* keep the HEC token as clear text in the configuration!

* The following example uses KMS to encrypt the HEC token. 
    ```
    module "hec_token_kms_secret" {
      source    = "disney/kinesis-firehose-splunk/aws//modules/kms_secrets"
      hec_token = "<KMS encrypted Splunk HEC token>"
    }

    module "vpc_flow_logs_to_splunk" {
      source          = "github.com/app-sre/terraform-aws-vpc-flow-logs-splunk?ref=v<your x.y.z>"
      vpc_id          = "<your vpc_id>
      hec_token       = module.hec_token_kms_secret.hec_token_kms_secret
      splunk_endpoint = "<your Splunk endpoint>"
    }
    ```

## Credits

A good deal of inspiration on how to work with Firehose provided by a similar module: 
[Send CloudWatch Logs to Splunk via Kinesis Firehose](https://github.com/disney/terraform-aws-kinesis-firehose-splunk)
