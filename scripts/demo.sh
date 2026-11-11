#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT/infra"
TABLE=$(terraform output -raw state_table_name)
URL=$(terraform output -raw health_url)
ALARM=$(terraform output -raw alarm_name)
echo "=== Normal health response ==="
curl -isS "$URL" || true
printf '\n=== Inject failure using authenticated AWS CLI ===\n'
aws dynamodb update-item --table-name "$TABLE" \
  --key '{"pk":{"S":"service-state"}}' \
  --update-expression 'SET #s = :bad' \
  --expression-attribute-names '{"#s":"status"}' \
  --expression-attribute-values '{":bad":{"S":"FAILED"}}' > /dev/null
printf '\n=== Cause one Lambda error to create CloudWatch metric ===\n'
curl -isS "$URL" || true
printf '\nA CloudWatch ALARM event should invoke recovery after metric evaluation (often a few minutes).\n'
echo "Monitor alarm with: aws cloudwatch describe-alarms --alarm-names '$ALARM' --query 'MetricAlarms[0].StateValue' --output text"
echo "Then re-test with: curl -i '$URL'"
echo "For manual reset (if needed), set status=HEALTHY in DynamoDB or run scripts/reset.sh"
