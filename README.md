# Send VPC Flow logs to Splunk via Kinesis Firehose

This module configures a Kinesis Firehose, sets up a subscription for a desired CloudWatch Log Group to the Firehose, and sends the log data to Splunk. A Lambda function is required to transform the VPC Log data to a format compatible with Splunk. This module takes care of configuring this Lambda function.

The Lambda function used is the one provided for AWS by Splunk: https://github.com/splunk/splunk-aws-firehose-flowlogs-processor

## Usage example

* Make sure your local Python interpreter is 3.8.x. This is what is currently targeted by splunk-aws-firehose-flowlogs-processo program.
* Call the module, e.g.:
```
module "vpc_flow_logs_to_splunk" {
  source          = "github.com/app-sre/terraform-aws-vpc-flow-logs-splunk:v<your x.y.z>"
  vpc_id          = "<your vpc_id>
  vpc_name        = "<your vpc_name>"
  hec_token       = "<KMS encrypted Splunk HEC token>"
  splunk_endpoint = "<your Splunk endpoint>"
}
```

## Credits

A good deal of inspiration on how to work with Firehose and Lambdas provided by a similar module: [Send CloudWatch Logs to Splunk via Kinesis Firehose](https://github.com/disney/terraform-aws-kinesis-firehose-splunk)
