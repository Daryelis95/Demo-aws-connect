locals {
  table_name = "${var.project_name}-${var.environment}-ConnectDemoData"
}

# ------------------------------------------------------------------
# Tabla DynamoDB — single-table design para todos los dominios
#
# Modelo de entidades:
#   PK                  | SK                   | Entidad
#   --------------------|----------------------|------------------
#   CUSTOMER#<id>       | PROFILE              | Perfil de cliente
#   CUSTOMER#<id>       | ORDER#<order_id>     | Pedido (Retail)
#   CUSTOMER#<id>       | CARD#<card_id>       | Tarjeta (Banca)
#   CUSTOMER#<id>       | TXN#<txn_id>         | Transacción (Banca)
# ------------------------------------------------------------------
resource "aws_dynamodb_table" "connect_demo" {
  name         = local.table_name
  billing_mode = var.billing_mode
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  # GSI para búsqueda por order_id o card_id sin conocer el customer_id
  attribute {
    name = "GSI1PK"
    type = "S"
  }

  attribute {
    name = "GSI1SK"
    type = "S"
  }

  global_secondary_index {
    name            = "GSI1"
    hash_key        = "GSI1PK"
    range_key       = "GSI1SK"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery
  }

  tags = merge(var.tags, {
    Name = local.table_name
  })
}
