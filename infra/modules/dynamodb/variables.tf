variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo en el nombre de la tabla."
  type        = string
}

variable "environment" {
  description = "Ambiente de despliegue (sandbox, staging, prod)."
  type        = string
}

variable "billing_mode" {
  description = "Modo de facturación de DynamoDB. PAY_PER_REQUEST recomendado para sandbox."
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.billing_mode)
    error_message = "billing_mode debe ser PAY_PER_REQUEST o PROVISIONED."
  }
}

variable "point_in_time_recovery" {
  description = "Habilitar Point-in-Time Recovery en la tabla."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags comunes que se aplican a la tabla DynamoDB."
  type        = map(string)
  default     = {}
}
