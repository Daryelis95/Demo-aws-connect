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
  description = "Nombre de la cola para el dominio Banca (flujos legacy)."
  type        = string
  default     = "BankingQueue"
}

# V3 ---------------------------------------------------------------
variable "fraud_queue_name" {
  description = "Nombre de la cola de alta prioridad para reportes de fraude (V3)."
  type        = string
  default     = "FraudQueue"
}

variable "banking_lex_bot_alias_arn" {
  description = <<-EOT
    ARN del alias activo de BankingFraudBot (Lex V2).
    Formato: arn:aws:lex:<region>:<account>:bot-alias/<botId>/<aliasId>
    Ejemplo del sandbox: arn:aws:lex:us-east-1:063103265536:bot-alias/NXHHCKVHHM/ZSII5DJKMX
    Este recurso vive fuera de Terraform (creado manualmente). No modificar el bot
    sin exportar su versión primero.
  EOT
  type        = string
}

variable "create_fraud_case_lambda_arn" {
  description = "ARN de la Lambda create-fraud-case (V3). Se crea con el módulo lambda."
  type        = string
}

variable "enable_banking_v3_flow" {
  description = <<-EOT
    Controla si se despliega el Contact Flow banking-v3.
    true  → crea aws_connect_contact_flow.banking_v3[0]
    false → destruye el recurso (el flujo v2 sigue activo en la consola).
  EOT
  type        = bool
  default     = true
}
# ------------------------------------------------------------------

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

variable "default_customer_queue_flow_id" {
  description = "ID del flujo 'Default customer queue' usado como QueueFlowId para la BankingQueue en el Escenario A (transacción legítima)."
  type        = string
}
