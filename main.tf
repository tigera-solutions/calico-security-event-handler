terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = "default"
  region  = var.region
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "local_file" "LambdaZipFile" {
  filename = "${path.module}/${var.zipfile}"
}

# Create an IAM role for API Gateway
resource "aws_iam_role" "APIGWRole" {
  assume_role_policy = <<POLICY1
{
  "Version" : "2012-10-17",
  "Statement" : [
    {
      "Effect" : "Allow",
      "Principal" : {
        "Service" : "apigateway.amazonaws.com"
      },
      "Action" : "sts:AssumeRole"
    }
  ]
}
POLICY1
}

# Create an IAM policy for API Gateway to write to create an EventBridge event
resource "aws_iam_policy" "APIGWPolicy" {
  policy = <<POLICY2
{
  "Version" : "2012-10-17",
  "Statement" : [
    {
      "Effect" : "Allow",
      "Action" : [
        "events:PutEvents"
      ],
      "Resource" : "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:event-bus/default"
    }
  ]
}
POLICY2
}

# Attach the IAM policies to the equivalent rule
resource "aws_iam_role_policy_attachment" "APIGWPolicyAttachment" {
  role       = aws_iam_role.APIGWRole.name
  policy_arn = aws_iam_policy.APIGWPolicy.arn
}

# Create an IAM role for Lambda
resource "aws_iam_role" "LambdaRole" {
  name               = "SecurityEventWebhookLambdaRole"
  assume_role_policy = <<POLICY3
{
  "Version" : "2012-10-17",
  "Statement" : [
    {
      "Effect" : "Allow",
      "Principal" : {
        "Service" : "lambda.amazonaws.com"
      },
      "Action" : "sts:AssumeRole"
    }
  ]
}
POLICY3
}

# Create an IAM policy for Lambda to push CloudWatch Logs
resource "aws_iam_policy" "LambdaPolicy" {
  policy = <<POLICY4
{
  "Version" : "2012-10-17",
  "Statement" : [
    {
      "Effect" : "Allow",
      "Action" : [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource" : "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${aws_lambda_function.MyLambdaFunction.function_name}:*:*"
    },
    {
      "Effect" : "Allow",
      "Action" : "eks:DescribeCluster",
      "Resource" : "*"
    }
  ]
}
POLICY4
}

# Attach the IAM policies to the equivalent rule
resource "aws_iam_role_policy_attachment" "LambdaPolicyAttachment" {
  role       = aws_iam_role.LambdaRole.name
  policy_arn = aws_iam_policy.LambdaPolicy.arn
}

# Create an API Gateway HTTP API with integration with EventBridge
resource "aws_apigatewayv2_api" "MyApiGatewayHTTPApi" {
  name          = "Terraform API Gateway HTTP API to EventBridge"
  protocol_type = "HTTP"
  body = jsonencode(
    {
      "openapi" : "3.0.1",
      "info" : {
        "title" : "API Gateway HTTP API to EventBridge"
      },
      "paths" : {
        "/" : {
          "post" : {
            "responses" : {
              "default" : {
                "description" : "EventBridge response"
              }
            },
            "x-amazon-apigateway-integration" : {
              "integrationSubtype" : "EventBridge-PutEvents",
              "credentials" : "${aws_iam_role.APIGWRole.arn}",
              "requestParameters" : {
                "Detail" : "$request.body",
                "DetailType" : "MyDetailType",
                "Source" : "demo.apigw"
              },
              "payloadFormatVersion" : "1.0",
              "type" : "aws_proxy",
              "connectionType" : "INTERNET"
            }
          }
        }
      }
  })
}

# Create an API Gateway Stage with automatic deployment
resource "aws_apigatewayv2_stage" "MyApiGatewayHTTPApiStage" {
  api_id      = aws_apigatewayv2_api.MyApiGatewayHTTPApi.id
  name        = "$default"
  auto_deploy = true
}

# Create a new Event Rule
resource "aws_cloudwatch_event_rule" "MyEventRule" {
  event_pattern = <<PATTERN
{
  "account": ["${data.aws_caller_identity.current.account_id}"],
  "source": ["demo.apigw"]
}
PATTERN
}

# Set the Lambda Function as a CloudWatch event target
resource "aws_cloudwatch_event_target" "MyRuleTarget" {
  arn  = aws_lambda_function.MyLambdaFunction.arn
  rule = aws_cloudwatch_event_rule.MyEventRule.id
}

# Create a log group for the Lambda function with 60 days retention period
resource "aws_cloudwatch_log_group" "MyLogGroup" {
  name              = "/aws/lambda/${aws_lambda_function.MyLambdaFunction.function_name}"
  retention_in_days = 1
}

# Create the Lambda function with the created Zip file of the source code
resource "aws_lambda_function" "MyLambdaFunction" {
  function_name    = "apigw-http-eventbridge-terraform-demo-${data.aws_caller_identity.current.account_id}"
  filename         = "${path.module}/LambdaFunction.zip"
  source_code_hash = data.local_file.LambdaZipFile.content_sha256
  role             = aws_iam_role.LambdaRole.arn
  handler          = "LambdaFunction.lambda_handler"
  runtime          = "python3.9"
}

# Allow the EventBridge rule created to invoke the Lambda function
resource "aws_lambda_permission" "EventBridgeLambdaPermission" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.MyLambdaFunction.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.MyEventRule.arn
}

output "APIGW-URL" {
  value       = aws_apigatewayv2_stage.MyApiGatewayHTTPApiStage.invoke_url
  description = "The API Gateway Invocation URL"
}

output "LambdaFunctionName" {
  value       = aws_lambda_function.MyLambdaFunction.function_name
  description = "The Lambda Function name"
}

output "CloudWatchLogName" {
  value       = "/aws/lambda/${aws_lambda_function.MyLambdaFunction.function_name}"
  description = "The Lambda Function Log Group"
}
