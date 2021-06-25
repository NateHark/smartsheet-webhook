variable "lambda_function" {}
variable "lambda_package" {}
variable "region" {}
variable "project" {}

provider "aws" {
  profile = "default"
  region  = var.region
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------------------------------------------------

# Provide manually when running "terraform apply" or set via the TF_VAR_smartsheet_access_token environment variable
variable "smartsheet_access_token" {
  description = " Smartsheet API access token"
  type        = string
  sensitive   = true
}

# ---------------------------------------------------------------------------------------------------------------------
# Lambda
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_iam_role" "lambda_exec_role" {
  name        = "${var.project}-lambda-exec-role"
  description = "Allows Lambda function to call AWS services on your behalf."

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_policy" "lambda_cloudwatch" {
  name        = "${var.project}-lambda-logging"
  description = "Allows Lambda function to write logs to CloudWatch"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_cloudwatch.arn
}

resource "aws_iam_policy" "lambda_secrets_manager" {
  name        = "${var.project}-secrets-manager"
  description = "Allows Lambda to create and retrieve secrets from Secrets Manager"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetResourcePolicy",
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret",
                "secretsmanager:ListSecretVersionIds",
                "secretsmanager:ListSecrets",
                "secretsmanager:CreateSecret"
            ],
            "Resource": [
                "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.project}/*"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_secrets_manager" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_secrets_manager.arn
}

resource "aws_lambda_function" "webhook" {
  description      = "Webhook callback Lambda function"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = var.lambda_function
  runtime          = "python3.8"
  filename         = var.lambda_package
  function_name    = var.project
  source_code_hash = base64sha256(filebase64(var.lambda_package))
  timeout          = 60

  environment {
    variables = {
      SECRET_PREFIX                       = var.project,
      SECRET_NAME_SMARTSHEET_ACCESS_TOKEN = "${var.project}/access_token"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_iam_role_policy_attachment.lambda_secrets_manager
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# Cloudwatch
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "default" {
  name = var.project
}

# ---------------------------------------------------------------------------------------------------------------------
# Secrets Manager
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "smartsheet_access_token" {
  name = "${var.project}/access_token"
}

resource "aws_secretsmanager_secret_version" "smartsheet_access_token" {
  secret_id     = aws_secretsmanager_secret.smartsheet_access_token.id
  secret_string = var.smartsheet_access_token
}

# ---------------------------------------------------------------------------------------------------------------------
# API Gateway
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "cloudwatch" {
  name        = "${var.project}-cloudwatch"
  description = "Allow API Gateway to write to CloudWatch"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "cloudwatch" {
  name = "${var.project}-cloudwatch-policy"
  role = aws_iam_role.cloudwatch.id

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams",
                "logs:PutLogEvents",
                "logs:GetLogEvents",
                "logs:FilterLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}

resource "aws_api_gateway_account" "default" {
  cloudwatch_role_arn = aws_iam_role.cloudwatch.arn
}

resource "aws_apigatewayv2_api" "smartsheet_webhook" {
  name          = var.project
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "smartsheet_webhook" {
  api_id           = aws_apigatewayv2_api.smartsheet_webhook.id
  integration_type = "AWS_PROXY"

  integration_method = "POST"
  integration_uri    = aws_lambda_function.webhook.arn
}

resource "aws_lambda_permission" "webhook" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.webhook.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.smartsheet_webhook.execution_arn}/*/*"
}

resource "aws_apigatewayv2_route" "webhook" {
  api_id    = aws_apigatewayv2_api.smartsheet_webhook.id
  route_key = "POST /webhook"
  target    = "integrations/${aws_apigatewayv2_integration.smartsheet_webhook.id}"
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.smartsheet_webhook.id
  name        = "prod"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.default.arn
    format          = "$context.identity.sourceIp - - [$context.requestTime] \"$context.httpMethod $context.routeKey $context.protocol\" $context.status $context.responseLength $context.requestId $context.error.messageString $context.integrationErrorMessage"
  }

  default_route_settings {
    throttling_burst_limit = 10
    throttling_rate_limit = 5
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------------------------------------------------

output "api_gateway_endpoint" {
  value = aws_apigatewayv2_stage.prod.invoke_url
  description = "The API Gateway endpoint URL"
}
