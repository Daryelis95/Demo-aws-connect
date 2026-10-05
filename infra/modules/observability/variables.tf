variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo en los recursos de observabilidad."
  type        = string
}

variable "environment" {
  description = "Ambiente de despliegue (sandbox, staging, prod)."
  type        = string
}

variable "aws_region" {
  description = "Región AWS donde se crean los recursos de observabilidad."
  type        = string
}

variable "log_retention_days" {
  description = "Días de retención de logs en CloudWatch."
  type        = number
  default     = 7
}

variable "enable_dashboard" {
  description = "Habilitar dashboard de CloudWatch para KPIs de la demo."
  type        = bool
  default     = true
}

variable "alarm_email" {
  description = "Email para notificaciones de alarmas CloudWatch (opcional)."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags comunes que se aplican a todos los recursos de observabilidad."
  type        = map(string)
  default     = {}
}
