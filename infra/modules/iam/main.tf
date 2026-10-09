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

# Política: invocar modelos de Amazon Bedrock directamente (bedrock-runtime)
resource "aws_iam_policy" "lambda_bedrock" {
  name        = "${local.prefix}-lambda-bedrock-policy"
  description = "Permite a las Lambdas invocar modelos de Amazon Bedrock via bedrock-runtime."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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

# Adjuntar políticas al rol Lambda
resource "aws_iam_role_policy_attachment" "lambda_cloudwatch" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.lambda_cloudwatch.arn
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.lambda_dynamodb.arn
}

resource "aws_iam_role_policy_attachment" "lambda_bedrock" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.lambda_bedrock.arn
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
          "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${local.prefix}-block-card",
          "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${local.prefix}-create-fraud-case"
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

# ------------------------------------------------------------------
# Rol exclusivo para create-fraud-case — permisos mínimos
# ------------------------------------------------------------------
resource "aws_iam_role" "create_fraud_case" {
  name = "${local.prefix}-create-fraud-case-role"

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

# Logs en CloudWatch (scope al log group propio)
resource "aws_iam_policy" "create_fraud_case_logs" {
  name        = "${local.prefix}-create-fraud-case-logs-policy"
  description = "Permite a create-fraud-case escribir logs en CloudWatch."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/lambda/${local.prefix}-create-fraud-case:*"
      }
    ]
  })

  tags = var.tags
}

# DynamoDB — solo la tabla del proyecto (GetItem, PutItem, UpdateItem)
resource "aws_iam_policy" "create_fraud_case_dynamodb" {
  name        = "${local.prefix}-create-fraud-case-dynamodb-policy"
  description = "Permite a create-fraud-case leer y escribir el ledger de fraude en DynamoDB."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = var.dynamodb_table_arn
      }
    ]
  })

  tags = var.tags
}

# Amazon Connect Cases — operaciones mínimas
resource "aws_iam_policy" "create_fraud_case_cases" {
  name        = "${local.prefix}-create-fraud-case-cases-policy"
  description = "Permite a create-fraud-case crear y vincular casos en Connect Cases."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cases:CreateCase",
          "cases:GetCase",
          "cases:CreateRelatedItem",
          "cases:SearchRelatedItems"
        ]
        Resource = [
          # ARN base del dominio (requerido por CreateCase)
          "arn:aws:cases:${var.aws_region}:${var.aws_account_id}:domain/${var.cases_domain_id}",
          # ARN de recursos hijos (casos, items relacionados, etc.)
          "arn:aws:cases:${var.aws_region}:${var.aws_account_id}:domain/${var.cases_domain_id}/*"
        ]
      }
    ]
  })

  tags = var.tags
}

# Customer Profiles — solo SearchProfiles para resolver el ProfileArn
resource "aws_iam_policy" "create_fraud_case_profiles" {
  name        = "${local.prefix}-create-fraud-case-profiles-policy"
  description = "Permite a create-fraud-case buscar perfiles en Customer Profiles."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["profile:SearchProfiles"]
        Resource = "arn:aws:profile:${var.aws_region}:${var.aws_account_id}:domains/${var.customer_profiles_domain_name}"
      }
    ]
  })

  tags = var.tags
}

# Adjuntar todas las políticas al rol
resource "aws_iam_role_policy_attachment" "create_fraud_case_logs" {
  role       = aws_iam_role.create_fraud_case.name
  policy_arn = aws_iam_policy.create_fraud_case_logs.arn
}

resource "aws_iam_role_policy_attachment" "create_fraud_case_dynamodb" {
  role       = aws_iam_role.create_fraud_case.name
  policy_arn = aws_iam_policy.create_fraud_case_dynamodb.arn
}

resource "aws_iam_role_policy_attachment" "create_fraud_case_cases" {
  role       = aws_iam_role.create_fraud_case.name
  policy_arn = aws_iam_policy.create_fraud_case_cases.arn
}

resource "aws_iam_role_policy_attachment" "create_fraud_case_profiles" {
  role       = aws_iam_role.create_fraud_case.name
  policy_arn = aws_iam_policy.create_fraud_case_profiles.arn
}
