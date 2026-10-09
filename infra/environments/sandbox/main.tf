locals {
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
  aws_account_id = data.aws_caller_identity.current.account_id
}

# ------------------------------------------------------------------
# Módulo: DynamoDB
# Debe desplegarse antes que IAM (IAM necesita el ARN de la tabla)
# ------------------------------------------------------------------
module "dynamodb" {
  source = "../../modules/dynamodb"

  project_name = var.project_name
  environment  = var.environment
  billing_mode = "PAY_PER_REQUEST"
  tags         = local.common_tags
}

# ------------------------------------------------------------------
# Módulo: IAM
# ------------------------------------------------------------------
module "iam" {
  source = "../../modules/iam"

  project_name       = var.project_name
  environment        = var.environment
  aws_region         = var.aws_region
  aws_account_id     = local.aws_account_id
  dynamodb_table_arn = module.dynamodb.table_arn
  tags               = local.common_tags

  # V3 — necesarios para el rol de create-fraud-case
  cases_domain_id               = var.cases_domain_id
  customer_profiles_domain_name = var.customer_profiles_domain_name
}

# ------------------------------------------------------------------
# Módulo: Lambda (tools)
# ------------------------------------------------------------------
module "lambda" {
  source = "../../modules/lambda"

  project_name              = var.project_name
  environment               = var.environment
  aws_region                = var.aws_region
  lambda_execution_role_arn = module.iam.lambda_execution_role_arn
  dynamodb_table_name       = module.dynamodb.table_name
  log_retention_days        = var.log_retention_days
  bedrock_model_id          = var.bedrock_model_id   # fix: antes no se pasaba al módulo
  tags                      = local.common_tags

  # V3 — variables para la Lambda create-fraud-case
  cases_domain_id               = var.cases_domain_id
  cases_template_id             = var.cases_template_id
  cases_field_ids               = var.cases_field_ids
  customer_profiles_domain_name = var.customer_profiles_domain_name
  create_fraud_case_role_arn    = module.iam.create_fraud_case_role_arn

  depends_on = [module.iam, module.dynamodb]
}

# ------------------------------------------------------------------
# Política inline: connect:DescribeContact para create-fraud-case
# Permite leer datos del contacto activo desde el flujo de Connect
# ------------------------------------------------------------------
resource "aws_iam_role_policy" "create_fraud_case_describe_contact" {
  name = "${var.project_name}-${var.environment}-describe-contact"
  role = module.iam.create_fraud_case_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["connect:DescribeContact"]
        Resource = "${module.connect.instance_arn}/contact/*"
      }
    ]
  })

  depends_on = [module.iam, module.connect]
}

# ------------------------------------------------------------------
# Módulo: Observabilidad (CloudWatch, alarmas, dashboard)
# ------------------------------------------------------------------
module "observability" {
  source = "../../modules/observability"

  project_name       = var.project_name
  environment        = var.environment
  aws_region         = var.aws_region
  log_retention_days = var.log_retention_days
  enable_dashboard   = true
  alarm_email        = var.alarm_email
  tags               = local.common_tags

  # Los metric filters de create-fraud-case necesitan que el log group
  # exista primero — ese log group lo crea el módulo lambda.
  depends_on = [module.lambda]
}

# ------------------------------------------------------------------
# Módulo: AgentCore (Bedrock Agent)
# ------------------------------------------------------------------
/*
module "agentcore" {
  source = "../../modules/agentcore"

  project_name                       = var.project_name
  environment                        = var.environment
  aws_region                         = var.aws_region
  aws_account_id                     = local.aws_account_id
  agentcore_execution_role_arn       = module.iam.agentcore_execution_role_arn
  bedrock_model_id                   = var.bedrock_model_id
  get_order_lambda_arn               = module.lambda.get_order_arn
  change_delivery_address_lambda_arn = module.lambda.change_delivery_address_arn
  get_transactions_lambda_arn        = module.lambda.get_transactions_arn
  block_card_lambda_arn              = module.lambda.block_card_arn
  tags                               = local.common_tags

  depends_on = [module.lambda, module.iam]
}
*/
# ------------------------------------------------------------------
# Módulo: Amazon Connect
# ------------------------------------------------------------------
module "connect" {
  source = "../../modules/connect"

  project_name                       = var.project_name
  environment                        = var.environment
  aws_region                         = var.aws_region
  connect_instance_alias             = var.connect_instance_alias
  retail_queue_name                  = var.retail_queue_name
  banking_queue_name                 = var.banking_queue_name
  agent_username                     = var.agent_username
  get_order_lambda_arn               = module.lambda.get_order_arn
  change_delivery_address_lambda_arn = module.lambda.change_delivery_address_arn
  get_transactions_lambda_arn        = module.lambda.get_transactions_arn
  block_card_lambda_arn              = module.lambda.block_card_arn
  tags                               = local.common_tags

  # V3 — Amazon Connect Cases
  fraud_queue_name             = var.fraud_queue_name
  banking_lex_bot_alias_arn    = var.banking_lex_bot_alias_arn
  create_fraud_case_lambda_arn = module.lambda.create_fraud_case_arn
  enable_banking_v3_flow       = var.enable_banking_v3_flow

  depends_on = [module.lambda]
}
