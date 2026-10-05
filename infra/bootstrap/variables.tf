variable "aws_region" {
  description = "Región AWS donde se crea el backend de Terraform."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nombre del proyecto. Usado como prefijo del bucket S3 y la tabla DynamoDB."
  type        = string
  default     = "connect-demo"
}

variable "state_bucket_suffix" {
  description = "Sufijo adicional para el nombre del bucket S3 (para garantizar unicidad global)."
  type        = string
  default     = ""
}
