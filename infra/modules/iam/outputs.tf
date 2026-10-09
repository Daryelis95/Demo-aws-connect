output "lambda_execution_role_arn" {
  description = "ARN del rol de ejecución de las funciones Lambda."
  value       = aws_iam_role.lambda_execution.arn
}

output "lambda_execution_role_name" {
  description = "Nombre del rol de ejecución de las funciones Lambda."
  value       = aws_iam_role.lambda_execution.name
}

output "connect_lambda_invoke_role_arn" {
  description = "ARN del rol que permite a Amazon Connect invocar Lambdas."
  value       = aws_iam_role.connect_lambda_invoke.arn
}

output "agentcore_execution_role_arn" {
  description = "ARN del rol de ejecución de Bedrock AgentCore."
  value       = aws_iam_role.agentcore_execution.arn
}

output "agentcore_execution_role_name" {
  description = "Nombre del rol de ejecución de Bedrock AgentCore."
  value       = aws_iam_role.agentcore_execution.name
}

output "create_fraud_case_role_arn" {
  description = "ARN del rol IAM exclusivo para la Lambda create-fraud-case."
  value       = aws_iam_role.create_fraud_case.arn
}

output "create_fraud_case_role_name" {
  description = "Nombre del rol IAM exclusivo para la Lambda create-fraud-case."
  value       = aws_iam_role.create_fraud_case.name
}
