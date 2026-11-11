"""Respond to a *specific* CloudWatch ALARM by restoring demo service state."""
import json
import os
from datetime import datetime, timezone


def handler(event, context):
    detail = event.get("detail", {})
    if (event.get("source") != "aws.cloudwatch"
            or event.get("detail-type") != "CloudWatch Alarm State Change"
            or detail.get("alarmName") != os.environ["EXPECTED_ALARM"]
            or detail.get("state", {}).get("value") != "ALARM"):
        return {"result": "ignored", "reason": "not our alarm transition"}

    import boto3
    ddb = boto3.client("dynamodb")
    try:
        # Conditional update makes repeated EventBridge deliveries idempotent.
        ddb.update_item(
            TableName=os.environ["STATE_TABLE"],
            Key={"pk": {"S": "service-state"}},
            UpdateExpression="SET #s = :healthy, last_recovered_at = :now",
            ConditionExpression="#s = :failed",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={
                ":healthy": {"S": "HEALTHY"}, ":failed": {"S": "FAILED"},
                ":now": {"S": datetime.now(timezone.utc).isoformat()},
            },
        )
    except ddb.exceptions.ConditionalCheckFailedException:
        print("No failure to remediate, skipping duplicate event")
        return {"result": "already-healthy"}

    message = {
        "project": "aws-cloudops-auto-healing-platform",
        "result": "recovered",
        "alarm": detail.get("alarmName"),
        "action": "Demo state changed from FAILED to HEALTHY",
        "time": datetime.now(timezone.utc).isoformat(),
    }
    print(json.dumps(message))
    try:
        boto3.client("sns").publish(
            TopicArn=os.environ["SNS_TOPIC_ARN"],
            Subject="CloudOps Demo: Service auto-recovered",
            Message=json.dumps(message, indent=2),
        )
    except Exception as exc:
        # Recovery happened; notification is best-effort, and recorded in logs.
        print(json.dumps({"level": "WARN", "notification_error": str(exc)}))
    return message
