variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo en los recursos de Amazon Connect."
  type        = string
}

variable "environment" {
  description = "Ambiente de despliegue (sandbox, staging, prod)."
  type        = string
}

variable "aws_region" {
  description = "Región AWS donde se despliega Amazon Connect."
  type        = string
}

variable "connect_instance_alias" {
  description = "Alias único de la instancia Amazon Connect (debe ser globalmente único)."
  type        = string
}

variable "identity_management_type" {
  description = "Tipo de gestión de identidad de la instancia Connect."
  type        = string
  default     = "CONNECT_MANAGED"

  validation {
    condition     = contains(["CONNECT_MANAGED", "SAML", "EXISTING_DIRECTORY"], var.identity_management_type)
    error_message = "identity_management_type debe ser CONNECT_MANAGED, SAML o EXISTING_DIRECTORY."
  }
}

variable "inbound_calls_enabled" {
  description = "Habilitar llamadas entrantes en la instancia."
  type        = bool
  default     = true
}

variable "outbound_calls_enabled" {
  description = "Habilitar llamadas salientes en la instancia."
  type        = bool
  default     = false
}

variable "retail_queue_name" {
  description = "Nombre de la cola para el dominio Retail."
  type        = string
  default     = "RetailQueue"
}

variable "banking_queue_name" {
  description = "Nombre de la cola para el dominio Banca."
  type        = string
  default     = "BankingQueue"
}

variable "agent_username" {
  description = "Username del agente humano creado en la instancia Connect."
  type        = string
  default     = "demo-agent"
}

variable "agent_first_name" {
  description = "Nombre del agente humano."
  type        = string
  default     = "Demo"
}

variable "agent_last_name" {
  description = "Apellido del agente humano."
  type        = string
  default     = "Agent"
}

variable "get_order_lambda_arn" {
  description = "ARN de la Lambda get-order para asociar con Connect."
  type        = string
}

variable "change_delivery_address_lambda_arn" {
  description = "ARN de la Lambda change-delivery-address para asociar con Connect."
  type        = string
}

variable "get_transactions_lambda_arn" {
  description = "ARN de la Lambda get-transactions para asociar con Connect."
  type        = string
}

variable "block_card_lambda_arn" {
  description = "ARN de la Lambda block-card para asociar con Connect."
  type        = string
}

variable "tags" {
  description = "Tags comunes que se aplican a todos los recursos de Amazon Connect."
  type        = map(string)
  default     = {}
}
