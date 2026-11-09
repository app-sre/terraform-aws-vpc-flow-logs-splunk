# Forward AWS logs to Splunk via Amazon Data Firehose

This repository contains:

* The root VPC Flow Logs module, which sends VPC Flow Logs directly to Firehose.
* `modules/cloudwatch-logs-to-firehose`, which subscribes one existing CloudWatch
  log group to a dedicated Firehose stream and sends its events to Splunk.
* `modules/splunk-firehose-connection`, the shared low-level Firehose connection.

The CloudWatch Logs module enables Firehose decompression and message extraction.
CloudWatch Logs sends gzip-compressed envelopes; Splunk requires the extracted
messages rather than those envelopes.

# Prerequisites

* Terraform >= 1.2.0
* AWS provider >= 5.59.0 and < 6.0.0
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

The root VPC module retains both destination types. The CloudWatch Logs module
currently supports only the native Splunk destination. Its interface keeps the
source identity separate from the destination so a tested Sumo Logic HTTP
adapter can be added later without changing the CloudWatch subscription model.

## CloudWatch Logs to Splunk

Use one module instance per independently identifiable log source. The source
log group must already exist; for RDS PostgreSQL it is normally created by the
consumer configuration before enabling `enabled_cloudwatch_logs_exports`.

```hcl
module "image_builder_database_logs" {
  source = "github.com/app-sre/terraform-aws-vpc-flow-logs-splunk//modules/cloudwatch-logs-to-firehose?ref=v<x.y.z>"

  name                      = "image-builder-prod-db-logs"
  cloudwatch_log_group_name = "/aws/rds/instance/image-builder-prod/postgresql"

  service_name = "image-builder"
  environment  = "production"
  source_id    = "aws:rds:us-east-1:123456789012:db:image-builder-prod/postgresql"

  splunk_endpoint                   = "https://<splunk-hec-endpoint>:8088"
  splunk_secrets_manager_secret_arn = aws_secretsmanager_secret.splunk_hec.arn
  splunk_index                      = "<approved-index>"
  splunk_sourcetype                 = "aws:rds:postgresql"
  splunk_host                       = "image-builder-prod"

  tags = {
    ManagedBy = "Terraform"
  }
}
```

The Secrets Manager secret must contain the JSON object expected by Firehose:

```json
{
  "hec_token": "<Splunk HEC token>"
}
```

Do not commit the secret value or pass it as a Terraform input. The module grants
the Firehose role `secretsmanager:GetSecretValue` only for the supplied secret.
If the secret uses a customer-managed KMS key, also set
`splunk_secrets_manager_kms_key_arn`.

### Source identity contract

Firehose message extraction deliberately removes CloudWatch envelope metadata.
Use a dedicated HEC token for each module instance and configure these token
defaults in Splunk:

* `source`: the module's `source_id`
* `sourcetype`: the module's `splunk_sourcetype`
* `host`: the module's `splunk_host`
* `index`: the module's `splunk_index`, with the token restricted to that index

The `required_splunk_hec_metadata` output exposes the expected values for review
and end-to-end verification. This contract prevents two database sources from
becoming indistinguishable after message extraction.

## Testing

The mocked test suite requires Terraform >= 1.7; the modules themselves remain
compatible with Terraform >= 1.2.

Run repository checks from the repository root:

```bash
terraform fmt -check -recursive
terraform init
terraform validate -no-color
terraform test -no-color
```

The native Terraform tests use a mocked AWS provider. They prove the resource
graph, least-privilege delivery policy, credential validation, CloudWatch Logs
processing configuration, and source metadata contract without contacting AWS.

Static and mocked tests do not prove delivery. Before production rollout, deploy
one non-production module instance and perform this end-to-end test:

1. Confirm the RDS instance exports `postgresql` logs and the expected CloudWatch
   log group receives a new event.
2. Generate a database event containing a unique correlation ID without placing
   credentials or sensitive data in the log message.
3. Confirm the CloudWatch subscription reports no `DeliveryErrors` or
   `DeliveryThrottling`.
4. Confirm Firehose reports successful decompression and a successful
   `DeliveryToSplunk` result, with no failed record under the backup S3 prefix.
5. Search Splunk for the correlation ID and verify `index`, `source`,
   `sourcetype`, and `host` against `required_splunk_hec_metadata`.
6. Verify an authorized Rover-group member can search the event and an
   unauthorized user cannot.
7. Repeat for every required Event of Interest and for each database/module
   instance.

If delivery fails, retain the Firehose error log entry, relevant metric window,
and redacted S3 failed-record metadata as evidence. Never include the HEC token
or raw sensitive database content in test artifacts.

See the complete [CloudWatch Logs to Splunk end-to-end validation runbook](docs/cloudwatch-logs-to-splunk-e2e.md)
for account verification, deployment, event generation, AWS/Splunk checks,
evidence requirements, failure triage, and rollback guidance.

## Security

The Kinesis Firehose backup S3 bucket (used for failed events / backup data, per `splunk_s3_backup_mode` / `http_endpoint_s3_backup_mode`) is hardened by default:

* **Public access blocked** — all four S3 public access block settings are enabled.
* **Versioned** — object versioning is enabled by default (`s3_versioning_enabled`, default `true`). It isn't needed by Firehose itself; it exists to satisfy policy-as-code guardrails that require versioning on every S3 bucket, so it can be turned off (`false`) if you don't need that.
* **Encrypted** — server-side encryption (SSE-S3 / `AES256`) is always enabled.
* **Lifecycle-managed** — objects expire after `s3_lifecycle_expiration_days` (default `90`); if `s3_versioning_enabled` is `true`, the underlying data is fully removed shortly after that rather than exactly on it. Incomplete multipart uploads are aborted after 7 days.

Public access blocking, encryption, and lifecycle management are not optional — this bucket only ever holds log/backup data, so there's no supported way to disable those. `s3_lifecycle_expiration_days` (retention window) and `s3_versioning_enabled` are configurable.

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
