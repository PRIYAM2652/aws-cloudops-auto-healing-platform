# Optional: only create these resources when an exact GitHub OIDC subject is supplied.
# A repo created after 2026-07-15 has immutable owner/repository IDs inside 'sub'.
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.github_oidc_subject == "" ? 0 : 1
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  tags           = local.tags
}
resource "aws_iam_role" "github" {
  count = var.github_oidc_subject == "" ? 0 : 1
  name  = "${local.prefix}-github-deploy"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github[0].arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = var.github_oidc_subject
        }
      }
    }]
  })
  tags = local.tags
}
resource "aws_iam_role_policy" "github_deploy" {
  count = var.github_oidc_subject == "" ? 0 : 1
  name  = "${local.prefix}-github-update-functions"
  role  = aws_iam_role.github[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:UpdateFunctionCode", "lambda:GetFunctionConfiguration"]
      Resource = [aws_lambda_function.app.arn, aws_lambda_function.remediate.arn]
    }]
  })
}
