output "function_arns" {
  description = "Mapa de nombre → ARN de cada función Lambda."
  value = {
    for key, fn in aws_lambda_function.tool : key => fn.arn
  }
}

output "function_names" {
  description = "Mapa de nombre → nombre real desplegado de cada función Lambda."
  value = {
    for key, fn in aws_lambda_function.tool : key => fn.function_name
  }
}

output "get_order_arn" {
  description = "ARN de la Lambda get-order."
  value       = aws_lambda_function.tool["get-order"].arn
}

output "change_delivery_address_arn" {
  description = "ARN de la Lambda change-delivery-address."
  value       = aws_lambda_function.tool["change-delivery-address"].arn
}

output "get_transactions_arn" {
  description = "ARN de la Lambda get-transactions."
  value       = aws_lambda_function.tool["get-transactions"].arn
}

output "block_card_arn" {
  description = "ARN de la Lambda block-card."
  value       = aws_lambda_function.tool["block-card"].arn
}
