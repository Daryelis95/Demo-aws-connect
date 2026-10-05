output "table_name" {
  description = "Nombre de la tabla DynamoDB ConnectDemoData."
  value       = aws_dynamodb_table.connect_demo.name
}

output "table_arn" {
  description = "ARN de la tabla DynamoDB ConnectDemoData."
  value       = aws_dynamodb_table.connect_demo.arn
}

output "table_id" {
  description = "ID de la tabla DynamoDB (coincide con el nombre)."
  value       = aws_dynamodb_table.connect_demo.id
}
