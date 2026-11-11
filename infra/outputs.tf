output "health_url" {
  description = "Public GET endpoint (read-only)."
  value       = "${aws_apigatewayv2_api.health.api_endpoint}/health"
}
output "state_table_name" { value = aws_dynamodb_table.state.name }
output "alarm_name" { value = aws_cloudwatch_metric_alarm.errors.alarm_name }
output "app_function_name" { value = aws_lambda_function.app.function_name }
output "remediate_function_name" { value = aws_lambda_function.remediate.function_name }
output "sns_topic_arn" { value = aws_sns_topic.incidents.arn }
output "github_role_arn" {
  value = var.github_oidc_subject == "" ? "(GitHub OIDC not configured yet)" : aws_iam_role.github[0].arn
}
