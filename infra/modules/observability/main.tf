locals {
  prefix = "${var.project_name}-${var.environment}"

  tool_functions = [
    "${local.prefix}-get-order",
    "${local.prefix}-change-delivery-address",
    "${local.prefix}-get-transactions",
    "${local.prefix}-block-card",
    "${local.prefix}-create-fraud-case"
  ]

  fraud_case_log_group = "/aws/lambda/${local.prefix}-create-fraud-case"

  fraud_metric_filters = {
    case_created        = { pattern = "{ $.event = \"case_created\" }",        description = "Casos de fraude creados exitosamente." }
    case_reused         = { pattern = "{ $.event = \"case_reused\" }",         description = "Casos reutilizados por deduplicación." }
    case_create_failed  = { pattern = "{ $.event = \"case_create_failed\" }",  description = "Fallos al crear el caso de fraude." }
    contact_link_failed = { pattern = "{ $.event = \"contact_link_failed\" }", description = "Fallos al vincular el contacto al caso." }
  }
}

# ------------------------------------------------------------------
# SNS Topic para alarmas (opcional, si se configura alarm_email)
# ------------------------------------------------------------------
resource "aws_sns_topic" "alarms" {
  name = "${local.prefix}-alarms"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "alarm_email" {
  count = var.alarm_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ------------------------------------------------------------------
# Alarma CloudWatch: errores en cualquier Lambda
# ------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = toset(local.tool_functions)

  alarm_name          = "${each.key}-errors"
  alarm_description   = "Errores en la función Lambda ${each.key}."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.key
  }

  alarm_actions = [aws_sns_topic.alarms.arn]

  tags = var.tags
}

# ------------------------------------------------------------------
# Dashboard de CloudWatch con KPIs principales de la demo
# ------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "demo_kpis" {
  count = var.enable_dashboard ? 1 : 0

  dashboard_name = "${local.prefix}-kpis"

  dashboard_body = jsonencode({
    widgets = [
      # --- Invocaciones totales de Lambdas ---
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Invocaciones de Tools"
          region = var.aws_region
          metrics = [
            for fn in local.tool_functions : ["AWS/Lambda", "Invocations", "FunctionName", fn]
          ]
          view   = "timeSeries"
          period = 300
          stat   = "Sum"
        }
      },
      # --- Errores de Lambdas ---
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Errores de Tools"
          region = var.aws_region
          metrics = [
            for fn in local.tool_functions : ["AWS/Lambda", "Errors", "FunctionName", fn]
          ]
          view   = "timeSeries"
          period = 300
          stat   = "Sum"
        }
      },
      # --- Duración promedio de Lambdas ---
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Duración Promedio (ms)"
          region = var.aws_region
          metrics = [
            for fn in local.tool_functions : ["AWS/Lambda", "Duration", "FunctionName", fn]
          ]
          view   = "timeSeries"
          period = 300
          stat   = "Average"
        }
      },
      # --- Throttles ---
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Throttles de Tools"
          region = var.aws_region
          metrics = [
            for fn in local.tool_functions : ["AWS/Lambda", "Throttles", "FunctionName", fn]
          ]
          view   = "timeSeries"
          period = 300
          stat   = "Sum"
        }
      }
    ]
  })
}

# ------------------------------------------------------------------
# Log Group para el agente AgentCore (trazas de razonamiento)
# ------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "agentcore" {
  name              = "/connect-demo/${local.prefix}/agentcore"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# ------------------------------------------------------------------
# Log Group para Amazon Connect (contact flow logs)
# ------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "connect" {
  name              = "/connect-demo/${local.prefix}/connect"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# ------------------------------------------------------------------
# Metric Filters — eventos de negocio de create-fraud-case
# Cada filtro extrae un contador del campo "event" en los logs JSON
# ------------------------------------------------------------------

resource "aws_cloudwatch_log_metric_filter" "fraud_case" {
  for_each = local.fraud_metric_filters

  name           = "${local.prefix}-fraud-${each.key}"
  log_group_name = local.fraud_case_log_group
  pattern        = each.value.pattern

  metric_transformation {
    name          = each.key
    namespace     = "${local.prefix}/FraudCase"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

# ------------------------------------------------------------------
# Alarma: case_create_failed > 0 en ventana de 5 minutos → SNS
# ------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "case_create_failed" {
  alarm_name          = "${local.prefix}-case-create-failed"
  alarm_description   = "Se produjo al menos un fallo al crear un caso de fraude en los últimos 5 minutos."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "case_create_failed"
  namespace           = "${local.prefix}/FraudCase"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]

  tags = var.tags

  depends_on = [aws_cloudwatch_log_metric_filter.fraud_case]
}
