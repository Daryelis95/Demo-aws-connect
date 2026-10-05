variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo en todos los recursos IAM."
  type        = string
}

variable "environment" {
  description = "Ambiente de despliegue (sandbox, staging, prod)."
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN de la tabla DynamoDB ConnectDemoData."
  type        = string
}

variable "aws_region" {
  description = "Región AWS donde se despliegan los recursos."
  type        = string
}

variable "aws_account_id" {
  description = "ID de la cuenta AWS."
  type        = string
}

variable "tags" {
  description = "Tags comunes que se aplican a todos los recursos IAM."
  type        = map(string)
  default     = {}
}
