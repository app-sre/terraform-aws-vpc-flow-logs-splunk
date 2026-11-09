# CloudWatch Logs to Splunk end-to-end validation

Use this runbook to validate one non-production instance of
`modules/cloudwatch-logs-to-firehose` before enabling it for the two production
image-builder databases covered by APPSRE-12447. Repeat the event checks for
each database and each required Event of Interest.

The test proves the runtime boundary that mocked Terraform tests cannot:

1. RDS writes an event to the intended CloudWatch log group.
2. The subscription sends it to the dedicated Firehose stream.
3. Firehose decompresses and extracts the CloudWatch Logs message.
4. Splunk indexes the event with the expected source identity.
5. The intended Rover group can search it and an unauthorized identity cannot.

## Safety and prerequisites

Coordinate the test window and correlation-ID format with the Splunk/security
team. If you deliberately generate an authentication failure, tell them first
so it is recognized as a validation event rather than an unexplained alert.

Before starting, obtain and record without guessing:

* The target non-production AWS account name and numeric account ID.
* The AWS Region and RDS instance identifier.
* The existing PostgreSQL CloudWatch log group name.
* A dedicated Splunk HEC endpoint and token for this source, with indexer
  acknowledgement enabled.
* The approved Splunk `index`, `source`, `sourcetype`, and `host` values.
* The ARN of a same-Region Secrets Manager secret containing only:

  ```json
  {"hec_token":"<token>"}
  ```

Never print or retrieve the secret value for this test. The HEC token defaults
must set `source`, `sourcetype`, `host`, and `index`; Firehose message extraction
intentionally removes the CloudWatch envelope that would otherwise identify the
log group.

Confirm the RDS instance exports `postgresql` logs and that the source log group
uses the Standard log class. A log group can have multiple subscription filters,
but review existing filters before adding another to avoid duplicate delivery.

## 1. Select and verify the AWS account

Run these commands from the consumer Terraform repository, not from this module
repository. Replace every placeholder with a verified value from the consumer's
authoritative configuration.

```bash
export E2E_AWS_ACCOUNT_NAME="<non-production-account-name>"
export E2E_AWS_ACCOUNT_ID="<12-digit-account-id>"
export E2E_AWS_REGION="<aws-region>"
export E2E_LOG_GROUP="/aws/rds/instance/<rds-id>/postgresql"

rh-aws-saml-login --account "$E2E_AWS_ACCOUNT_NAME"
aws sts get-caller-identity
```

Stop if the returned account ID is not exactly `E2E_AWS_ACCOUNT_ID`. Set the
consumer repository's normal AWS profile/Region variables as required; do not
substitute credentials from Vault unless an approved SOP explicitly requires it.

Confirm the source and secret metadata without reading log or secret contents:

```bash
aws logs describe-log-groups \
  --region "$E2E_AWS_REGION" \
  --log-group-name-prefix "$E2E_LOG_GROUP" \
  --query "logGroups[?logGroupName=='$E2E_LOG_GROUP'].{name:logGroupName,class:logGroupClass}"

aws logs describe-subscription-filters \
  --region "$E2E_AWS_REGION" \
  --log-group-name "$E2E_LOG_GROUP" \
  --query 'subscriptionFilters[].{name:filterName,destination:destinationArn}'

aws secretsmanager describe-secret \
  --region "$E2E_AWS_REGION" \
  --secret-id "<splunk-hec-secret-arn>" \
  --query '{arn:ARN,kmsKeyId:KmsKeyId,lastChanged:LastChangedDate}'
```

## 2. Configure one non-production module instance

For pre-merge validation, pin the module to this feature branch. After release,
replace the branch reference with the released immutable tag.

```hcl
module "image_builder_database_logs_e2e" {
  source = "git::ssh://git@github.com/app-sre/terraform-aws-vpc-flow-logs-splunk.git//modules/cloudwatch-logs-to-firehose?ref=feature/APPSRE-12447"

  name                      = "image-builder-<environment>-db-logs"
  cloudwatch_log_group_name = "/aws/rds/instance/<rds-id>/postgresql"

  service_name = "image-builder"
  environment  = "<non-production-environment>"
  source_id    = "aws:rds:<region>:<account-id>:db:<rds-id>/postgresql"

  splunk_endpoint                   = "https://<splunk-hec-endpoint>:8088"
  splunk_secrets_manager_secret_arn = "<splunk-hec-secret-arn>"
  splunk_index                      = "<approved-index>"
  splunk_sourcetype                 = "aws:rds:postgresql"
  splunk_host                       = "<rds-id>"

  tags = {
    ManagedBy = "Terraform"
    Ticket    = "APPSRE-12447"
  }
}

output "delivery_stream_name" {
  value = module.image_builder_database_logs_e2e.delivery_stream_name
}

output "backup_bucket_name" {
  value = module.image_builder_database_logs_e2e.backup_bucket_name
}

output "subscription_filter_name" {
  value = module.image_builder_database_logs_e2e.subscription_filter_name
}

output "required_splunk_hec_metadata" {
  value = module.image_builder_database_logs_e2e.required_splunk_hec_metadata
}
```

Run the consumer repository's normal setup and validation targets. At minimum:

```bash
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=APPSRE-12447-e2e.tfplan
terraform show APPSRE-12447-e2e.tfplan
```

Review the retained plan before applying it. It should create one dedicated
Firehose stream, one failed-event S3 bucket, delivery-monitoring logs, scoped
Firehose and CloudWatch Logs roles, and one subscription filter on the selected
source log group. It must not modify the RDS instance or another log group.

Apply only after the normal infrastructure approval for the target account:

```bash
terraform apply APPSRE-12447-e2e.tfplan
```

Capture the outputs without exposing any secret:

```bash
terraform output delivery_stream_name
terraform output backup_bucket_name
terraform output subscription_filter_name
terraform output -json required_splunk_hec_metadata
```

## 3. Verify the deployed transport

Copy the three non-secret Terraform outputs into task-specific shell variables:

```bash
export E2E_FIREHOSE_STREAM="<delivery_stream_name>"
export E2E_BACKUP_BUCKET="<backup_bucket_name>"
export E2E_SUBSCRIPTION_FILTER="<subscription_filter_name>"
export E2E_FAILED_OBJECTS_BEFORE="$(aws s3api list-objects-v2 \
  --region "$E2E_AWS_REGION" \
  --bucket "$E2E_BACKUP_BUCKET" \
  --prefix cloudwatch-logs/ \
  --query 'length(Contents)' \
  --output text)"
```

Verify the stream is active and the subscription targets its ARN:

```bash
aws firehose describe-delivery-stream \
  --region "$E2E_AWS_REGION" \
  --delivery-stream-name "$E2E_FIREHOSE_STREAM" \
  --query 'DeliveryStreamDescription.{status:DeliveryStreamStatus,arn:DeliveryStreamARN,destination:Destinations[0].DestinationId}'

aws logs describe-subscription-filters \
  --region "$E2E_AWS_REGION" \
  --log-group-name "$E2E_LOG_GROUP" \
  --filter-name-prefix "$E2E_SUBSCRIPTION_FILTER" \
  --query 'subscriptionFilters[].{name:filterName,destination:destinationArn,role:roleArn,pattern:filterPattern}'
```

Expected result: the stream is `ACTIVE`, exactly one matching subscription is
present, and its destination ARN names `E2E_FIREHOSE_STREAM`.

## 4. Generate a traceable Event of Interest

Create a unique, non-secret correlation ID shorter than PostgreSQL's identifier
limit and record the UTC start time:

```bash
export E2E_CORRELATION_ID="appsre12447e2e$(date -u +%Y%m%d%H%M%S)"
export E2E_START_TIME="$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)"
```

Use the consumer team's approved method to produce an Event of Interest. For a
coordinated failed-login test, connect once with `E2E_CORRELATION_ID` as a
deliberately nonexistent PostgreSQL user and a deliberately invalid, non-secret
password. Do not use or log a real credential. If failed-login tests are not
approved, use another ticket-required event that is known to be emitted by the
current PostgreSQL logging configuration.

Wait at least three minutes, then verify that the correlation ID reached the
source log group. Return only a count to avoid copying raw database logs into the
test record:

```bash
aws logs filter-log-events \
  --region "$E2E_AWS_REGION" \
  --log-group-name "$E2E_LOG_GROUP" \
  --filter-pattern "$E2E_CORRELATION_ID" \
  --start-time "$(date -u -d "$E2E_START_TIME" +%s000)" \
  --query 'length(events)' \
  --output text
```

Expected result: at least one matching source event. If it is zero, stop and fix
RDS export/logging before diagnosing the module.

## 5. Verify CloudWatch Logs and Firehose delivery

Discover the emitted CloudWatch Logs metric dimensions rather than assuming a
provider-specific destination label:

```bash
aws cloudwatch list-metrics \
  --region "$E2E_AWS_REGION" \
  --namespace AWS/Logs \
  --metric-name DeliveryErrors \
  --dimensions Name=LogGroupName,Value="$E2E_LOG_GROUP" Name=FilterName,Value="$E2E_SUBSCRIPTION_FILTER" \
  --query 'Metrics[].Dimensions'

aws cloudwatch list-metrics \
  --region "$E2E_AWS_REGION" \
  --namespace AWS/Firehose \
  --metric-name DeliveryToSplunk.Success \
  --dimensions Name=DeliveryStreamName,Value="$E2E_FIREHOSE_STREAM"
```

In CloudWatch, inspect the test window for:

* `AWS/Logs` `DeliveryErrors` and `DeliveryThrottling`: both must sum to zero.
* `AWS/Firehose` `IncomingRecords`: must increase.
* `AWS/Firehose` `DeliveryToSplunk.Records` and
  `DeliveryToSplunk.Success`: must increase.
* `AWS/Firehose` `DeliveryToSplunk.DataFreshness`: must return toward zero.

Check that Firehose emitted no delivery error and that the failed-event prefix
did not gain a new object during the test window:

```bash
aws logs filter-log-events \
  --region "$E2E_AWS_REGION" \
  --log-group-name "/aws/kinesisfirehose/$E2E_FIREHOSE_STREAM" \
  --log-stream-names SplunkDelivery \
  --start-time "$(date -u -d "$E2E_START_TIME" +%s000)" \
  --query 'length(events)' \
  --output text

export E2E_FAILED_OBJECTS_AFTER="$(aws s3api list-objects-v2 \
  --region "$E2E_AWS_REGION" \
  --bucket "$E2E_BACKUP_BUCKET" \
  --prefix cloudwatch-logs/ \
  --query 'length(Contents)' \
  --output text)"

test "$E2E_FAILED_OBJECTS_AFTER" -eq "$E2E_FAILED_OBJECTS_BEFORE"
```

Expected result: zero Firehose error-log events and no new failed-event object.
Do not download failed objects into task output; inspect redacted metadata only.

## 6. Verify Splunk identity and access

Use the values from `required_splunk_hec_metadata`, not inferred values. Search:

```spl
index="<index>"
source="<source>"
sourcetype="<sourcetype>"
host="<host>"
"<E2E_CORRELATION_ID>"
| stats count min(_time) as first_seen max(_time) as last_seen
```

The count must be at least one. Inspect one event only far enough to confirm that
the payload is the extracted PostgreSQL message rather than an `awslogs` gzip or
JSON envelope. Record only the count, timestamps, and metadata fields; do not
paste raw database log content into Jira or a pull request.

Finally:

* Confirm an intended Rover-group member can run the search.
* Confirm a test identity outside the authorized group cannot search the index.
* Repeat the event generation and search for every ticket-required Event of
  Interest.
* Repeat the full source-identity check for the second image-builder database,
  using its own module instance and dedicated HEC token.

## 7. Evidence and pass criteria

Attach a redacted validation summary containing:

* AWS account name and ID, Region, environment, and RDS identifier.
* Module Git ref and consumer plan/apply revision.
* Delivery stream, subscription filter, and backup bucket names.
* Correlation ID and UTC test window.
* Source-event count, zero delivery errors/throttles, Firehose delivery counts,
  and zero failed S3 objects.
* Verified Splunk `index`, `source`, `sourcetype`, and `host` values.
* Authorized and unauthorized access-test outcomes.
* One result for every required Event of Interest and both databases.

The test passes only when the event is present at every stage, source identity is
correct, no delivery failure is recorded, and the authorization checks behave as
expected.

## Failure triage and rollback

Classify the failing boundary before changing infrastructure:

* No CloudWatch event: RDS export or PostgreSQL logging configuration.
* `DeliveryErrors`: CloudWatch Logs role, subscription, or destination ARN.
* Firehose input but no Splunk success: HEC endpoint/token/indexer
  acknowledgement, Secrets Manager/KMS access, or Splunk availability.
* Failed S3 object: inspect Firehose's error code and redacted object metadata.
* Event indexed with wrong identity: dedicated HEC token defaults do not match
  `required_splunk_hec_metadata`.

To remove a temporary non-production deployment, first retain the redacted
evidence, then run and review `terraform plan -destroy`. Obtain the normal
destructive-change approval before `terraform destroy`. Removing the subscription
stops new forwarding; it does not remove events already indexed in Splunk. The
versioned backup bucket may require a separately approved retention/cleanup plan
if it contains objects.
