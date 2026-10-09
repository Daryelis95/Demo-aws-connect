variable "aws_region" {
  description = "Región AWS donde se despliegan todos los recursos."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nombre del proyecto. Usado como prefijo en todos los recursos."
  type        = string
  default     = "connect-demo"
}

variable "environment" {
  description = "Ambiente de despliegue."
  type        = string
  default     = "sandbox"
}

variable "connect_instance_alias" {
  description = "Alias único de la instancia Amazon Connect (globalmente único en AWS)."
  type        = string
  default     = "connect-demo-sandbox"
}

variable "bedrock_model_id" {
  description = "ID del modelo de Bedrock para el agente."
  type        = string
  default     = "anthropic.claude-3-sonnet-20240229-v1:0"
}

variable "retail_queue_name" {
  description = "Nombre de la cola de Retail en Amazon Connect."
  type        = string
  default     = "RetailQueue"
}

variable "banking_queue_name" {
  description = "Nombre de la cola de Banca en Amazon Connect."
  type        = string
  default     = "BankingQueue"
}

variable "log_retention_days" {
  description = "Días de retención de logs en CloudWatch."
  type        = number
  default     = 7
}

variable "alarm_email" {
  description = "Email para notificaciones de alarmas CloudWatch (dejar vacío para deshabilitar)."
  type        = string
  default     = ""
}

variable "agent_username" {
  description = "Username del agente humano de demo en Amazon Connect."
  type        = string
  default     = "demo-agent"
}

variable "tags" {
  description = "Tags adicionales aplicados a todos los recursos."
  type        = map(string)
  default     = {}
}

# =============================================================================
# V3 — Amazon Connect Cases
# Estos valores se obtienen manualmente desde la consola AWS y se colocan
# en terraform.tfvars (no versionado). Ver .kiro/v3-cases-fraude-bancario.md §4.
# =============================================================================

variable "fraud_queue_name" {
  description = "Nombre de la cola de alta prioridad para reportes de fraude (V3)."
  type        = string
  default     = "FraudQueue"
}

variable "enable_banking_v3_flow" {
  description = "Despliega el Contact Flow banking-v3 cuando es true. Usar false para rollback sin destruir."
  type        = bool
  default     = true
}

variable "banking_lex_bot_alias_arn" {
  description = <<-EOT
    ARN del alias activo de BankingFraudBot (Lex V2). Recurso fuera de Terraform.
    Sandbox: arn:aws:lex:us-east-1:063103265536:bot-alias/NXHHCKVHHM/ZSII5DJKMX
  EOT
  type        = string
}

variable "cases_domain_id" {
  description = <<-EOT
    ID del dominio de Amazon Connect Cases asociado a la instancia bancaria.
    Se crea en la consola (Fase A §4.2) y se registra aquí.
    Ejemplo: abcd1234-00aa-11bb-22cc-ddddeeeeffff
  EOT
  type        = string
}

variable "cases_template_id" {
  description = <<-EOT
    ID de la plantilla "Reporte de fraude bancario" en Connect Cases.
    Obtener con: aws connectcases list-templates --domain-id <domain-id>
  EOT
  type        = string
}

variable "cases_field_ids" {
  description = <<-EOT
    JSON con el mapa de nombre lógico → fieldId real en el dominio Cases.
    Obtener con: aws connectcases list-fields --domain-id <domain-id>
    Claves requeridas: customerId, transactionId, cardReference, blockResult,
                       blockedAt, consent, operationId, priority, contactId.
    Formato: '{"customerId":"uuid","transactionId":"uuid",...}'
  EOT
  type        = string
  default     = "{}"
}

variable "customer_profiles_domain_name" {
  description = <<-EOT
    Nombre del dominio de Amazon Connect Customer Profiles asociado a la instancia.
    Ejemplo: amazon-connect-connect-demo-sandbox-banking
    Ver en Connect > instancia > Customer Profiles.
  EOT
  type        = string
}

variable "default_customer_queue_flow_id" {
  description = "ID del flujo 'Default customer queue' de Connect (QueueFlowId para BankingQueue en Escenario A)."
  type        = string
}
