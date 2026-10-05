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
