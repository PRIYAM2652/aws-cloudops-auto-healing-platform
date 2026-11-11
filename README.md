# AWS CloudOps Auto-Healing Platform

**Terraform + AWS Lambda + API Gateway + DynamoDB + CloudWatch + EventBridge + SNS + GitHub Actions CI**

A small, cost-aware AWS operational automation project for CloudOps / DevOps / SRE interviews. It demonstrates a **controlled application fault** detected by native Lambda telemetry, followed by **event-driven state remediation**. It does *not* reboot actual instances or recover physical infrastructure.

## Architecture

```mermaid
flowchart TD
  GH[GitHub Actions CI] --> BUILD[Unit tests and Lambda ZIP artifacts]
  API[API Gateway GET /health] --> L
  L -->|GetItem| DB[(DynamoDB demo state)]
  L -->|Unhandled error metric| CW[CloudWatch Alarm]
  CW -->|State change to ALARM| EB[EventBridge Rule]
  EB --> R[Remediation Lambda]
  R -->|Conditional UpdateItem| DB
  R --> S[SNS incident email]
```

## Security and cost decisions

- No EC2, EKS, NAT gateway, load balancer, VPC endpoints, RDS or always-on worker.
- One low-capacity provisioned DynamoDB table, two 128-MB Lambdas using account-level concurrency, one CloudWatch alarm, one EventBridge rule and a small SNS topic.
- **Public endpoint supports only `GET /health`**; failure injection requires authenticated AWS CLI permissions. API rate-limited at the gateway.
- Application IAM policy allows only `dynamodb:GetItem`; remediation policy allows only `dynamodb:UpdateItem` and `sns:Publish` for the specific resources.
- GitHub Actions tests and packages code without AWS credentials. Terraform deployment is performed through AWS CloudShell.
- Lambda log retention is three days. Public APIs can still receive traffic and costs can arise on some plans; always check credits/billing and destroy unused resources.
- Terraform state is local in AWS CloudShell and ignored by Git. Keep CloudShell `$HOME` data safe; do not delete `.tfstate` or commit it.

## Prerequisites

1. AWS console with CloudShell access and permissions to create Lambda, API Gateway, DynamoDB, CloudWatch, EventBridge, SNS and IAM resources.
2. AWS region chosen, preferably the region from your AWS project.
3. Optional: email for SNS alerts; later confirm the subscription email.
4. Optional: a **public GitHub repository** for CI/CD.

## 1. Download and deploy from AWS CloudShell

In AWS Console click the **CloudShell (`>_`)** icon. Use **Actions → Upload file** to upload `aws-cloudops-auto-healing-platform.zip` from your laptop. Then:

```bash
unzip -oq aws-cloudops-auto-healing-platform.zip
cd aws-cloudops-auto-healing-platform
bash scripts/install-terraform.sh
export PATH="$HOME/.local/bin:$PATH"
aws sts get-caller-identity
aws configure get region
```

Choose the project region, if needed (example Mumbai):

```bash
export TF_VAR_aws_region="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-south-1}}"
```

Add an alert email **optionally**:

```bash
export TF_VAR_notification_email="your-email@example.com"
```

To avoid accidentally routing alerts to someone else's inbox, set the variable to your own email only. Omit this line if you don't want email alerts yet.

```bash
cd infra
terraform init
terraform validate
terraform plan
terraform apply
terraform output
curl -i "$(terraform output -raw health_url)"
```

Type `yes` to approve the plan. Terraform might fail if AWS Free plan restricts a specific service or if your identity lacks IAM permissions; do not upgrade to a Paid plan just to get around a restriction.

## 2. Demonstrate the auto-healing sequence

From the repo root:

```bash
cd ..
bash scripts/demo.sh
```

The script displays a successful health check, changes DynamoDB `status` to `FAILED` with the authenticated AWS CLI and sends exactly one failed health request. Watch the metric alarm and EventBridge recovery in AWS Console. Detection typically occurs after CloudWatch metric evaluation, so it is not instantaneous.

```bash
cd infra
aws cloudwatch describe-alarms \
  --alarm-names "$(terraform output -raw alarm_name)" \
  --query 'MetricAlarms[0].{State:StateValue,Updated:StateUpdatedTimestamp}'

aws logs tail /aws/lambda/cloudops-demo-remediate --since 15m
curl -i "$(terraform output -raw health_url)"
```

Expected final response: `200` with JSON containing `"status": "healthy"`. On the console, capture: a failing API response, CloudWatch ALARM history, EventBridge invocation / recovery Lambda logs, successful API response, and SNS email if subscribed.

If the CloudWatch alarm was already in ALARM from a previous attempt, it may not emit another *state-change* event. Reset the state, wait until CloudWatch shows OK, then rerun the demo.

To manually reset:

```bash
cd ..
bash scripts/reset.sh
```

## 3. GitHub Actions CI

Repository: https://github.com/PRIYAM2652/aws-cloudops-auto-healing-platform

Pushes to main automatically trigger GitHub Actions to:

1. Check out the source code.
2. Set up Python 3.12.
3. Execute the unit tests.
4. Package both Lambda functions.
5. Upload ZIP build artifacts.

The pipeline was verified successful on November 11, 2026.

AWS deployment is managed separately through Terraform
in AWS CloudShell. Automated deployment using GitHub OIDC
was evaluated but blocked by an AWS Organizations SCP
denying iam:CreateOpenIDConnectProvider.

No permanent AWS access keys are stored in GitHub.

### Verified Auto-Healing Results

- Initial health check: HTTP 200
- Simulated failure: HTTP 500
- CloudWatch: OK to ALARM
- EventBridge invoked the remediation Lambda
- DynamoDB: FAILED to HEALTHY
- Final API response: HTTP 200
- Recovery duration: approximately 105 seconds

## 4. Run tests

```bash
python3 -m unittest discover -s tests -v
```

The tests don't need AWS credentials, and boto3 is mocked.

## 5. Destroy to avoid continuing charges

In the same CloudShell region and with the same Terraform state:

```bash
cd infra
terraform destroy
```

**Cleanup:** Use the original Terraform state in CloudShell to destroy the managed resources when the lab is no longer required.

## Troubleshooting

| Symptom | Check |
|---|---|
| `terraform: command not found` | Run `bash scripts/install-terraform.sh` and `export PATH="$HOME/.local/bin:$PATH"`. |
| `AccessDenied` for IAM/Lambda | Verify current project/account and your IAM permissions; Free plan restrictions may apply. |
| `curl /health` gives 404 | Copy the **Terraform health_url output**, including `/health`. |
| `curl` gives 5xx before injection | Inspect `aws logs tail /aws/lambda/cloudops-demo-app --since 10m`; verify DynamoDB table initial item, IAM GetItem and function environment. |
| No remediation | Check `aws cloudwatch describe-alarms`, EventBridge rule status, and remediation Lambda CloudWatch logs. Alarm needs a transition to ALARM. |
| No alert email | Check SNS subscription confirmation email; use SNS console to check pending subscriptions. |
| GitHub OIDC AccessDenied | Check exact `sub` including owner/repo numeric IDs, branch `main`, repository Variables and role ARN. |
| CloudShell storage lost | Restore the **original Terraform state** before managing previously created resources; do not blindly apply a new state or duplicate resources. |

## Interview talking points

**Problem:** An app can enter a failed state; relying solely on on-call staff is slow.

**Solution:** Terraform provisions an event-driven system; CloudWatch detects errors; EventBridge invokes a least-privilege recovery Lambda; DynamoDB transitions back to healthy; SNS notifies an operator; GitHub Actions validates and packages the Lambda code.

**Operational insight:** Auto-healing here is *application-state remediation*, not real server repair. Tradeoffs include alarm evaluation delay, idempotence and conditional writes, notification delivery, exposure of public health endpoints, lack of guaranteed exactly-once delivery, and tracking Terraform state separately from CI code updates.

**Resume bullet:** Built a Terraform-managed AWS application auto-healing demo with Lambda, API Gateway, DynamoDB, CloudWatch alarms, EventBridge, SNS and GitHub Actions CI, validating fault injection, automated recovery and application health.
