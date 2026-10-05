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
  description = "ID de la cola Banca."
  value       = aws_connect_queue.banking.queue_id
}

output "banking_queue_arn" {
  description = "ARN de la cola Banca."
  value       = aws_connect_queue.banking.arn
}

output "routing_profile_id" {
  description = "ID del Routing Profile compartido."
  value       = aws_connect_routing_profile.main.routing_profile_id
}

output "retail_contact_flow_id" {
  description = "ID del Contact Flow de Retail."
  value       = aws_connect_contact_flow.retail.contact_flow_id
}

output "banking_contact_flow_id" {
  description = "ID del Contact Flow de Banca."
  value       = aws_connect_contact_flow.banking.contact_flow_id
}

output "demo_agent_id" {
  description = "ID del usuario agente de demo en Amazon Connect."
  value       = aws_connect_user.demo_agent.user_id
}
