"""Demo application: public read-only health endpoint.

For a reproducible interview demo, failure is injected with authenticated
AWS CLI access to DynamoDB, NOT through an unsecured public API endpoint.
"""
import json
import os
from datetime import datetime, timezone


def handler(event, context):
    path = event.get("rawPath", "/")
    if path != "/health":
        return {"statusCode": 404, "headers": {"content-type": "application/json"},
                "body": json.dumps({"message": "Use GET /health"})}

    # Boto3 is included in the AWS Lambda Python runtime.
    import boto3
    response = boto3.client("dynamodb").get_item(
        TableName=os.environ["STATE_TABLE"],
        Key={"pk": {"S": "service-state"}},
        ConsistentRead=True,
    )
    status = response.get("Item", {}).get("status", {}).get("S", "HEALTHY")
    if status != "HEALTHY":
        # A real unhandled Lambda error produces an AWS/Lambda Errors metric.
        # API Gateway returns a 5xx response to the caller.
        print(json.dumps({"level": "ERROR", "service_status": status, "message": "Simulated failure"}))
        raise RuntimeError("Simulated application failure — CloudWatch should alarm")

    return {
        "statusCode": 200,
        "headers": {"content-type": "application/json", "cache-control": "no-store"},
        "body": json.dumps({"status": "healthy", "service": "cloudops-auto-healing",
                            "time": datetime.now(timezone.utc).isoformat()}),
    }
