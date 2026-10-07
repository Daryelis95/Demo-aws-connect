locals {
  prefix = "${var.project_name}-${var.environment}"

  # Lista de tools con sus propiedades
  tools = {
    get-order = {
      handler     = "handler.lambda_handler"
      description = "Consulta el estado de un pedido por order_id (Retail)."
      source_dir  = "${path.root}/../../../src/tools/get_order"
    }
    change-delivery-address = {
      handler     = "handler.lambda_handler"
      description = "Cambia la dirección de entrega de un pedido (Retail)."
      source_dir  = "${path.root}/../../../src/tools/change_delivery_address"
    }
    get-transactions = {
      handler     = "handler.lambda_handler"
      description = "Consulta movimientos recientes de un cliente (Banca)."
      source_dir  = "${path.root}/../../../src/tools/get_transactions"
    }
    block-card = {
      handler     = "handler.lambda_handler"
      description = "Bloquea una tarjeta bancaria ante fraude, robo o pérdida (Banca)."
      source_dir  = "${path.root}/../../../src/tools/block_card"
    }
  }
}

# ------------------------------------------------------------------
# Empaquetar el código fuente de cada Lambda en un zip
# ------------------------------------------------------------------
data "archive_file" "lambda_zip" {
  for_each = local.tools

  type        = "zip"
  source_dir  = each.value.source_dir
  output_path = "${path.module}/.build/${each.key}.zip"
}

# ------------------------------------------------------------------
# Funciones Lambda — una por cada tool
# ------------------------------------------------------------------
resource "aws_lambda_function" "tool" {
  for_each = local.tools

  function_name = "${local.prefix}-${each.key}"
  description   = each.value.description
  role          = var.lambda_execution_role_arn
  handler       = each.value.handler
  runtime       = var.python_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  filename         = data.archive_file.lambda_zip[each.key].output_path
  source_code_hash = data.archive_file.lambda_zip[each.key].output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = var.dynamodb_table_name
      ENVIRONMENT         = var.environment
      LOG_LEVEL           = var.log_level
      AWS_REGION_NAME     = var.aws_region
      BEDROCK_MODEL_ID    = var.bedrock_model_id
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]

  tags = merge(var.tags, {
    Name = "${local.prefix}-${each.key}"
  })
}

# ------------------------------------------------------------------
# Log Groups en CloudWatch — uno por función, con retención definida
# ------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda" {
  for_each = local.tools

  name              = "/aws/lambda/${local.prefix}-${each.key}"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Function = "${local.prefix}-${each.key}"
  })
}

# ------------------------------------------------------------------
# Permiso para que Amazon Connect invoque cada Lambda
# ------------------------------------------------------------------
resource "aws_lambda_permission" "allow_connect" {
  for_each = local.tools

  statement_id  = "AllowConnectInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.tool[each.key].function_name
  principal     = "connect.amazonaws.com"
}
