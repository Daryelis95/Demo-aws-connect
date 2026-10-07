output "dynamodb_table_name" {
  description = "Nombre de la tabla DynamoDB."
  value       = module.dynamodb.table_name
}

output "dynamodb_table_arn" {
  description = "ARN de la tabla DynamoDB."
  value       = module.dynamodb.table_arn
}

output "lambda_function_arns" {
  description = "ARNs de las funciones Lambda (tools)."
  value       = module.lambda.function_arns
}
/*
output "bedrock_agent_id" {
  description = "ID del agente Bedrock."
  value       = module.agentcore.agent_id
}

output "bedrock_agent_alias_id" {
  description = "ID del alias del agente Bedrock para sandbox."
  value       = module.agentcore.agent_alias_id
}
*/
output "connect_instance_id" {
  description = "ID de la instancia Amazon Connect."
  value       = module.connect.instance_id
}

output "connect_instance_arn" {
  description = "ARN de la instancia Amazon Connect."
  value       = module.connect.instance_arn
}

output "retail_queue_id" {
  description = "ID de la cola Retail en Amazon Connect."
  value       = module.connect.retail_queue_id
}

output "banking_queue_id" {
  description = "ID de la cola Banca en Amazon Connect."
  value       = module.connect.banking_queue_id
}

output "retail_contact_flow_id" {
  description = "ID del Contact Flow de Retail."
  value       = module.connect.retail_contact_flow_id
}

output "banking_contact_flow_id" {
  description = "ID del Contact Flow de Banca."
  value       = module.connect.banking_contact_flow_id
}

output "cloudwatch_dashboard_name" {
  description = "Nombre del dashboard de CloudWatch."
  value       = module.observability.dashboard_name
}

output "alarms_sns_topic_arn" {
  description = "ARN del SNS topic de alarmas."
  value       = module.observability.alarms_sns_topic_arn
}
