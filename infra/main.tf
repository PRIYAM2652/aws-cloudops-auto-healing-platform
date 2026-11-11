locals {
  prefix = "cloudops-demo"
  tags = {
    Project   = "cloudops-auto-healing"
    ManagedBy = "terraform"
    Purpose   = "portfolio-lab"
  }
}

data "archive_file" "app" {
  type        = "zip"
  source_file = "${path.module}/../src/app.py"
  output_path = "${path.module}/app.zip"
}

data "archive_file" "remediate" {
  type        = "zip"
  source_file = "${path.module}/../src/remediate.py"
  output_path = "${path.module}/remediate.zip"
}

resource "aws_dynamodb_table" "state" {
  name           = "${local.prefix}-state"
  billing_mode   = "PROVISIONED"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "pk"
  attribute {
    name = "pk"
    type = "S"
  }
  tags = local.tags
}

resource "aws_dynamodb_table_item" "initial" {
  lifecycle {
    ignore_changes = [item]
  }
  table_name = aws_dynamodb_table.state.name
  hash_key   = aws_dynamodb_table.state.hash_key
  item = jsonencode({
    pk     = { S = "service-state" }
    status = { S = "HEALTHY" }
  })
}

resource "aws_iam_role" "app" {
  name = "${local.prefix}-app-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" },
    Action = "sts:AssumeRole" }]
  })
  tags = local.tags
}
resource "aws_iam_role" "remediate" {
  name = "${local.prefix}-remediate-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" },
    Action = "sts:AssumeRole" }]
  })
  tags = local.tags
}
resource "aws_iam_role_policy_attachment" "app_logs" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy_attachment" "remediate_logs" {
  role       = aws_iam_role.remediate.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy" "app_state_read" {
  name = "${local.prefix}-app-read"
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["dynamodb:GetItem"],
    Resource = aws_dynamodb_table.state.arn }]
  })
}

resource "aws_sns_topic" "incidents" {
  name = "${local.prefix}-incidents"
  tags = local.tags
}
resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.incidents.arn
  protocol  = "email"
  endpoint  = var.notification_email
}
resource "aws_iam_role_policy" "remediate_actions" {
  name = "${local.prefix}-remediate-actions"
  role = aws_iam_role.remediate.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["dynamodb:UpdateItem"], Resource = aws_dynamodb_table.state.arn },
      { Effect = "Allow", Action = ["sns:Publish"], Resource = aws_sns_topic.incidents.arn },
    ]
  })
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/aws/lambda/${local.prefix}-app"
  retention_in_days = 3
  tags              = local.tags
}
resource "aws_cloudwatch_log_group" "remediate" {
  name              = "/aws/lambda/${local.prefix}-remediate"
  retention_in_days = 3
  tags              = local.tags
}

resource "aws_lambda_function" "app" {
  function_name    = "${local.prefix}-app"
  description      = "Read-only health endpoint for auto-healing demo"
  filename         = data.archive_file.app.output_path
  source_code_hash = data.archive_file.app.output_base64sha256
  role             = aws_iam_role.app.arn
  handler          = "app.handler"
  runtime          = "python3.12"
  memory_size      = 128
  timeout          = 5
  environment { variables = { STATE_TABLE = aws_dynamodb_table.state.name } }
  depends_on = [aws_iam_role_policy_attachment.app_logs, aws_iam_role_policy.app_state_read, aws_cloudwatch_log_group.app]
  lifecycle { ignore_changes = [source_code_hash] } # CI/CD owns code updates, Terraform owns infra.
  tags = local.tags
}

resource "aws_lambda_function" "remediate" {
  function_name    = "${local.prefix}-remediate"
  description      = "Event-driven demo recovery from DynamoDB FAILED state"
  filename         = data.archive_file.remediate.output_path
  source_code_hash = data.archive_file.remediate.output_base64sha256
  role             = aws_iam_role.remediate.arn
  handler          = "remediate.handler"
  runtime          = "python3.12"
  memory_size      = 128
  timeout          = 10
  environment { variables = {
    STATE_TABLE    = aws_dynamodb_table.state.name
    EXPECTED_ALARM = "${local.prefix}-app-errors"
    SNS_TOPIC_ARN  = aws_sns_topic.incidents.arn
  } }
  depends_on = [aws_iam_role_policy_attachment.remediate_logs, aws_iam_role_policy.remediate_actions, aws_cloudwatch_log_group.remediate]
  lifecycle { ignore_changes = [source_code_hash] }
  tags = local.tags
}

resource "aws_apigatewayv2_api" "health" {
  name          = "${local.prefix}-api"
  protocol_type = "HTTP"
  tags          = local.tags
}
resource "aws_apigatewayv2_integration" "app" {
  api_id                 = aws_apigatewayv2_api.health.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.app.invoke_arn
  payload_format_version = "2.0"
}
resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.health.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.app.id}"
}
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.health.id
  name        = "$default"
  auto_deploy = true
  default_route_settings {
    throttling_burst_limit = 5
    throttling_rate_limit  = 2
  }
  tags = local.tags
}
resource "aws_lambda_permission" "api" {
  statement_id  = "AllowApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.health.execution_arn}/*/GET/health"
}

resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${local.prefix}-app-errors"
  alarm_description   = "One or more unhandled app Lambda errors in a 60-second period"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  dimensions          = { FunctionName = aws_lambda_function.app.function_name }
  tags                = local.tags
}
resource "aws_cloudwatch_event_rule" "auto_recovery" {
  name        = "${local.prefix}-auto-recovery"
  description = "Invoke remediation when the app Lambda error alarm changes to ALARM"
  event_pattern = jsonencode({
    source        = ["aws.cloudwatch"]
    "detail-type" = ["CloudWatch Alarm State Change"]
    detail        = { alarmName = [aws_cloudwatch_metric_alarm.errors.alarm_name], state = { value = ["ALARM"] } }
  })
  tags = local.tags
}
resource "aws_cloudwatch_event_target" "remediate" {
  rule      = aws_cloudwatch_event_rule.auto_recovery.name
  target_id = "DemoRecoveryLambda"
  arn       = aws_lambda_function.remediate.arn
}
resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediate.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.auto_recovery.arn
}
