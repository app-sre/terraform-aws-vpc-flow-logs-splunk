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
