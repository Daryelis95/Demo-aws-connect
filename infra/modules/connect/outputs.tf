output "instance_id" {
  description = "ID de la instancia Amazon Connect."
  value       = aws_connect_instance.main.id
}

output "instance_arn" {
  description = "ARN de la instancia Amazon Connect."
  value       = aws_connect_instance.main.arn
}

output "retail_queue_id" {
  description = "ID de la cola Retail."
  value       = aws_connect_queue.retail.queue_id
}

output "retail_queue_arn" {
  description = "ARN de la cola Retail."
  value       = aws_connect_queue.retail.arn
}

output "banking_queue_id" {
  description = "ID de la cola Banca (legacy)."
  value       = aws_connect_queue.banking.queue_id
}

output "banking_queue_arn" {
  description = "ARN de la cola Banca (legacy)."
  value       = aws_connect_queue.banking.arn
}

# V3 ---------------------------------------------------------------
output "fraud_queue_id" {
  description = "ID de la cola FraudQueue (V3)."
  value       = aws_connect_queue.fraud.queue_id
}

output "fraud_queue_arn" {
  description = "ARN de la cola FraudQueue (V3)."
  value       = aws_connect_queue.fraud.arn
}
# ------------------------------------------------------------------

output "routing_profile_id" {
  description = "ID del Routing Profile compartido."
  value       = aws_connect_routing_profile.main.routing_profile_id
}

output "retail_contact_flow_id" {
  description = "ID del Contact Flow de Retail."
  value       = aws_connect_contact_flow.retail.contact_flow_id
}

output "banking_contact_flow_id" {
  description = "ID del Contact Flow de Banca (original)."
  value       = aws_connect_contact_flow.banking.contact_flow_id
}

# V3 ---------------------------------------------------------------
output "banking_v3_contact_flow_id" {
  description = "ID del Contact Flow de Banca V3 (Cases). Null si enable_banking_v3_flow = false."
  value       = var.enable_banking_v3_flow ? aws_connect_contact_flow.banking_v3[0].contact_flow_id : null
}

output "banking_v3_contact_flow_arn" {
  description = "ARN del Contact Flow de Banca V3 (Cases). Null si enable_banking_v3_flow = false."
  value       = var.enable_banking_v3_flow ? aws_connect_contact_flow.banking_v3[0].arn : null
}
# ------------------------------------------------------------------

output "demo_agent_id" {
  description = "ID del usuario agente de demo en Amazon Connect."
  value       = aws_connect_user.demo_agent.user_id
}
