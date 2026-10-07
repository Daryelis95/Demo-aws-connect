# ------------------------------------------------------------------
# Outputs del módulo agentcore
#
# Deshabilitados mientras se usa invocación directa de Bedrock desde Lambda.
# Descomentar si se reactiva aws_bedrockagent_agent.
# ------------------------------------------------------------------

# output "agent_id" {
#   description = "ID del agente Bedrock."
#   value       = aws_bedrockagent_agent.main.id
# }

# output "agent_arn" {
#   description = "ARN del agente Bedrock."
#   value       = aws_bedrockagent_agent.main.agent_arn
# }

# output "agent_alias_id" {
#   description = "ID del alias del agente Bedrock."
#   value       = aws_bedrockagent_agent_alias.sandbox.agent_alias_id
# }

# output "agent_alias_arn" {
#   description = "ARN del alias del agente Bedrock."
#   value       = aws_bedrockagent_agent_alias.sandbox.agent_alias_arn
# }
