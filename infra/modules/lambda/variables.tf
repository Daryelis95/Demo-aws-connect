variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo en los nombres de las funciones Lambda."
  type        = string
}

variable "environment" {
  description = "Ambiente de despliegue (sandbox, staging, prod)."
  type        = string
}

variable "aws_region" {
  description = "Región AWS donde se despliegan las funciones Lambda."
  type        = string
}

variable "lambda_execution_role_arn" {
  description = "ARN del rol IAM de ejecución para las funciones Lambda."
  type        = string
}

variable "dynamodb_table_name" {
  description = "Nombre de la tabla DynamoDB ConnectDemoData."
  type        = string
}

variable "python_runtime" {
  description = "Runtime de Python para las funciones Lambda."
  type        = string
  default     = "python3.11"
}

variable "lambda_timeout" {
  description = "Timeout en segundos para las funciones Lambda."
  type        = number
  default     = 30
}

variable "lambda_memory_size" {
  description = "Memoria en MB asignada a cada función Lambda."
  type        = number
  default     = 256
}

variable "log_retention_days" {
  description = "Días de retención de logs en CloudWatch para las funciones Lambda."
  type        = number
  default     = 7
}

variable "log_level" {
  description = "Nivel de logging de las funciones Lambda (DEBUG, INFO, WARNING, ERROR)."
  type        = string
  default     = "INFO"
}

variable "bedrock_model_id" {
  description = "ID del modelo de Amazon Bedrock usado para generar mensajes conversacionales."
  type        = string
  default     = "anthropic.claude-sonnet-4-6"
}

variable "tags" {
  description = "Tags comunes que se aplican a todas las funciones Lambda."
  type        = map(string)
  default     = {}
}
