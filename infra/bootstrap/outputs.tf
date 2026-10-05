output "state_bucket_name" {
  description = "Nombre del bucket S3 para el estado de Terraform."
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  description = "ARN del bucket S3 para el estado de Terraform."
  value       = aws_s3_bucket.terraform_state.arn
}

output "lock_table_name" {
  description = "Nombre de la tabla DynamoDB para el locking del estado."
  value       = aws_dynamodb_table.terraform_locks.id
}

output "lock_table_arn" {
  description = "ARN de la tabla DynamoDB para el locking del estado."
  value       = aws_dynamodb_table.terraform_locks.arn
}

output "backend_config_hint" {
  description = "Bloque backend sugerido para infra/environments/sandbox/main.tf"
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.terraform_state.id}"
        key            = "sandbox/terraform.tfstate"
        region         = "${var.aws_region}"
        dynamodb_table = "${aws_dynamodb_table.terraform_locks.id}"
        encrypt        = true
      }
    }
  EOT
}
