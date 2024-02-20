# Send VPC Flow logs to Splunk via Kinesis Firehose

This module configures a Kinesis Firehose, sets up a subscription for a desired CloudWatch Log Group to the Firehose, and sends the log data to Splunk.

According to [AWS Big Data Blog](https://aws.amazon.com/blogs/big-data/ingest-vpc-flow-logs-into-splunk-using-amazon-kinesis-data-firehose/), a Lambda is no longer required to transform the VPC flow logs according to the 7.3.0 version in Splunk AWS Add-on, hence this module does not contain any Lambda processing any more. If you need to send data to a Splunk system with an older Add-on, please take a look to v0.1.0 of this module.

## Usage

* The following example uses KMS to encrypt the HEC token. You can use that or whatever mechanism you have to avoid storing the HEC token in plain text, e.g. a parameter store.
* Call the module, e.g.:
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

A good deal of inspiration on how to work with Firehose provided by a similar module: [Send CloudWatch Logs to Splunk via Kinesis Firehose](https://github.com/disney/terraform-aws-kinesis-firehose-splunk)
