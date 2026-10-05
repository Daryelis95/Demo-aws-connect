variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo en los recursos AgentCore."
  type        = string
}

variable "environment" {
  description = "Ambiente de despliegue (sandbox, staging, prod)."
  type        = string
}

variable "aws_region" {
  description = "Región AWS donde se despliegan los recursos de AgentCore."
  type        = string
}

variable "aws_account_id" {
  description = "ID de la cuenta AWS."
  type        = string
}

variable "agentcore_execution_role_arn" {
  description = "ARN del rol IAM de ejecución para Bedrock AgentCore."
  type        = string
}

variable "bedrock_model_id" {
  description = "ID del modelo de Bedrock a utilizar (ej: anthropic.claude-3-sonnet-20240229-v1:0)."
  type        = string
  default     = "anthropic.claude-3-sonnet-20240229-v1:0"
}

variable "agent_name" {
  description = "Nombre del agente Bedrock."
  type        = string
  default     = "connect-demo-agent"
}

variable "agent_description" {
  description = "Descripción del agente Bedrock."
  type        = string
  default     = "Agente de Amazon Connect para demo Retail y Banca."
}

variable "get_order_lambda_arn" {
  description = "ARN de la Lambda get-order."
  type        = string
}

variable "change_delivery_address_lambda_arn" {
  description = "ARN de la Lambda change-delivery-address."
  type        = string
}

variable "get_transactions_lambda_arn" {
  description = "ARN de la Lambda get-transactions."
  type        = string
}

variable "block_card_lambda_arn" {
  description = "ARN de la Lambda block-card."
  type        = string
}

variable "idle_session_ttl_seconds" {
  description = "Tiempo de inactividad en segundos antes de cerrar la sesión del agente."
  type        = number
  default     = 600
}

variable "tags" {
  description = "Tags comunes que se aplican a todos los recursos de AgentCore."
  type        = map(string)
  default     = {}
}
