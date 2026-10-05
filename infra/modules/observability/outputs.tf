output "alarms_sns_topic_arn" {
  description = "ARN del SNS topic para notificaciones de alarmas."
  value       = aws_sns_topic.alarms.arn
}

output "agentcore_log_group_name" {
  description = "Nombre del Log Group de CloudWatch para AgentCore."
  value       = aws_cloudwatch_log_group.agentcore.name
}

output "connect_log_group_name" {
  description = "Nombre del Log Group de CloudWatch para Amazon Connect."
  value       = aws_cloudwatch_log_group.connect.name
}

output "dashboard_name" {
  description = "Nombre del dashboard de CloudWatch con KPIs."
  value       = var.enable_dashboard ? aws_cloudwatch_dashboard.demo_kpis[0].dashboard_name : null
}
