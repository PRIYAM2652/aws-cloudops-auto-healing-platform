#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT/infra"
TABLE=$(terraform output -raw state_table_name)
aws dynamodb update-item --table-name "$TABLE" \
  --key '{"pk":{"S":"service-state"}}' \
  --update-expression 'SET #s = :good' \
  --expression-attribute-names '{"#s":"status"}' \
  --expression-attribute-values '{":good":{"S":"HEALTHY"}}' > /dev/null
echo 'Reset demo state to HEALTHY.'
