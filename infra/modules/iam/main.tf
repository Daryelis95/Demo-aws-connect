locals {
  prefix = "${var.project_name}-${var.environment}"
}

# ------------------------------------------------------------------
# Rol de ejecución para las funciones Lambda (tools)
# ------------------------------------------------------------------
resource "aws_iam_role" "lambda_execution" {
  name = "${local.prefix}-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

# Política: escritura de logs en CloudWatch
resource "aws_iam_policy" "lambda_cloudwatch" {
  name        = "${local.prefix}-lambda-cloudwatch-policy"
  description = "Permite a las Lambdas escribir logs en CloudWatch Logs."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/lambda/${local.prefix}-*:*"
      }
    ]
  })

  tags = var.tags
}

# Política: acceso a DynamoDB (lectura y escritura, solo sobre la tabla del proyecto)
resource "aws_iam_policy" "lambda_dynamodb" {
  name        = "${local.prefix}-lambda-dynamodb-policy"
  description = "Permite a las Lambdas leer y escribir en la tabla ConnectDemoData."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          var.dynamodb_table_arn,
          "${var.dynamodb_table_arn}/index/*"
        ]
      }
    ]
  })

  tags = var.tags
}

# Adjuntar políticas al rol Lambda
resource "aws_iam_role_policy_attachment" "lambda_cloudwatch" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.lambda_cloudwatch.arn
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.lambda_dynamodb.arn
}

# ------------------------------------------------------------------
# Rol para Amazon Connect — invocar Lambdas
# ------------------------------------------------------------------
resource "aws_iam_role" "connect_lambda_invoke" {
  name = "${local.prefix}-connect-lambda-invoke-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "connect.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_policy" "connect_lambda_invoke" {
  name        = "${local.prefix}-connect-lambda-invoke-policy"
  description = "Permite a Amazon Connect invocar las Lambdas de la demo."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
        Resource = [
          "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${local.prefix}-get-order",
          "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${local.prefix}-change-delivery-address",
          "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${local.prefix}-get-transactions",
          "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${local.prefix}-block-card"
        ]
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "connect_lambda_invoke" {
  role       = aws_iam_role.connect_lambda_invoke.name
  policy_arn = aws_iam_policy.connect_lambda_invoke.arn
}

# ------------------------------------------------------------------
# Rol para Bedrock AgentCore — invocar Lambdas (tools)
# ------------------------------------------------------------------
resource "aws_iam_role" "agentcore_execution" {
  name = "${local.prefix}-agentcore-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "bedrock.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_policy" "agentcore_lambda_invoke" {
  name        = "${local.prefix}-agentcore-lambda-invoke-policy"
  description = "Permite a Bedrock AgentCore invocar las Lambdas (tools) de la demo."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
        Resource = [
          "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${local.prefix}-get-order",
          "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${local.prefix}-change-delivery-address",
          "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${local.prefix}-get-transactions",
          "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${local.prefix}-block-card"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/*"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "agentcore_lambda_invoke" {
  role       = aws_iam_role.agentcore_execution.name
  policy_arn = aws_iam_policy.agentcore_lambda_invoke.arn
}
