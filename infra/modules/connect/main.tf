# ------------------------------------------------------------------
# NOTA DE SOPORTE TERRAFORM
#
# El provider hashicorp/aws >= 5.x incluye soporte para los recursos
# principales de Amazon Connect.
# ------------------------------------------------------------------

locals {
  prefix = "${var.project_name}-${var.environment}"
}

# ------------------------------------------------------------------
# Instancia Amazon Connect (compartida para Retail y Banca)
# ------------------------------------------------------------------
resource "aws_connect_instance" "main" {
  identity_management_type = var.identity_management_type
  inbound_calls_enabled    = var.inbound_calls_enabled
  outbound_calls_enabled   = var.outbound_calls_enabled
  instance_alias           = var.connect_instance_alias

  tags = merge(var.tags, {
    Name   = var.connect_instance_alias
    Shared = "true"
  })
}

# ------------------------------------------------------------------
# Asociar Lambdas con la instancia Connect
# ------------------------------------------------------------------
resource "aws_connect_lambda_function_association" "get_order" {
  instance_id  = aws_connect_instance.main.id
  function_arn = var.get_order_lambda_arn
}

resource "aws_connect_lambda_function_association" "change_delivery_address" {
  instance_id  = aws_connect_instance.main.id
  function_arn = var.change_delivery_address_lambda_arn
}

resource "aws_connect_lambda_function_association" "get_transactions" {
  instance_id  = aws_connect_instance.main.id
  function_arn = var.get_transactions_lambda_arn
}

resource "aws_connect_lambda_function_association" "block_card" {
  instance_id  = aws_connect_instance.main.id
  function_arn = var.block_card_lambda_arn
}

# ------------------------------------------------------------------
# Horario de atención (24x7 para la demo)
# ------------------------------------------------------------------
resource "aws_connect_hours_of_operation" "all_day" {
  instance_id = aws_connect_instance.main.id
  name        = "${local.prefix}-24x7"
  description = "Horario 24x7 para la demo."
  time_zone   = "America/New_York"

  dynamic "config" {
    for_each = ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"]
    content {
      day = config.value
      end_time {
        hours   = 23
        minutes = 59
      }
      start_time {
        hours   = 0
        minutes = 0
      }
    }
  }

  tags = var.tags
}

# ------------------------------------------------------------------
# Security Profile compartido para agentes de la demo
# ------------------------------------------------------------------
resource "aws_connect_security_profile" "agent" {
  instance_id = aws_connect_instance.main.id
  name        = "${local.prefix}-agent-profile"
  description = "Perfil de seguridad para agentes de la demo (Retail + Banca)."

  permissions = [
    "BasicAgentAccess",
    "OutboundCallAccess"
  ]

  tags = var.tags
}

# ------------------------------------------------------------------
# Cola Retail
# ------------------------------------------------------------------
resource "aws_connect_queue" "retail" {
  instance_id           = aws_connect_instance.main.id
  name                  = var.retail_queue_name
  description           = "Cola de atención para el dominio Retail."
  hours_of_operation_id = aws_connect_hours_of_operation.all_day.hours_of_operation_id

  tags = merge(var.tags, {
    Domain = "RETAIL"
  })
}

# ------------------------------------------------------------------
# Cola Banca
# ------------------------------------------------------------------
resource "aws_connect_queue" "banking" {
  instance_id           = aws_connect_instance.main.id
  name                  = var.banking_queue_name
  description           = "Cola de atención para el dominio Banca."
  hours_of_operation_id = aws_connect_hours_of_operation.all_day.hours_of_operation_id

  tags = merge(var.tags, {
    Domain = "BANKING"
  })
}

# ------------------------------------------------------------------
# Routing Profile (comparte las dos colas)
# ------------------------------------------------------------------
resource "aws_connect_routing_profile" "main" {
  instance_id               = aws_connect_instance.main.id
  name                      = "${local.prefix}-routing-profile"
  description               = "Routing profile compartido para Retail y Banca."
  default_outbound_queue_id = aws_connect_queue.retail.queue_id

  media_concurrencies {
    channel     = "VOICE"
    concurrency = 1
  }

  media_concurrencies {
    channel     = "CHAT"
    concurrency = 3
  }

  queue_configs {
    channel  = "VOICE"
    delay    = 0
    priority = 1
    queue_id = aws_connect_queue.retail.queue_id
  }

  queue_configs {
    channel  = "VOICE"
    delay    = 0
    priority = 2
    queue_id = aws_connect_queue.banking.queue_id
  }

  queue_configs {
    channel  = "CHAT"
    delay    = 0
    priority = 1
    queue_id = aws_connect_queue.retail.queue_id
  }

  queue_configs {
    channel  = "CHAT"
    delay    = 0
    priority = 2
    queue_id = aws_connect_queue.banking.queue_id
  }

  tags = var.tags
}

# ------------------------------------------------------------------
# Usuario agente de demo
# ------------------------------------------------------------------
resource "aws_connect_user" "demo_agent" {
  instance_id        = aws_connect_instance.main.id
  name               = var.agent_username
  password           = "DemoPassword123!"
  routing_profile_id = aws_connect_routing_profile.main.routing_profile_id
  security_profile_ids = [
    aws_connect_security_profile.agent.security_profile_id
  ]

  identity_info {
    first_name = var.agent_first_name
    last_name  = var.agent_last_name
  }

  phone_config {
    phone_type = "SOFT_PHONE"
  }

  tags = var.tags
}

# ------------------------------------------------------------------
# Contact Flow — Retail
# ------------------------------------------------------------------
resource "aws_connect_contact_flow" "retail" {
  instance_id = aws_connect_instance.main.id
  name        = "${local.prefix}-retail-flow"
  description = "Contact flow para el dominio Retail (consulta y modificación de pedidos)."
  type        = "CONTACT_FLOW"

  content = templatefile("${path.module}/flows/retail.json", {
    retail_queue_id = aws_connect_queue.retail.queue_id
  })

  tags = merge(var.tags, {
    Domain = "RETAIL"
  })
}

# ------------------------------------------------------------------
# Contact Flow — Banca
# ------------------------------------------------------------------
resource "aws_connect_contact_flow" "banking" {
  instance_id = aws_connect_instance.main.id
  name        = "${local.prefix}-banking-flow"
  description = "Contact flow para el dominio Banca (transacciones y bloqueo de tarjeta)."
  type        = "CONTACT_FLOW"

  content = templatefile("${path.module}/flows/banking.json", {
    banking_queue_id = aws_connect_queue.banking.queue_id
  })

  tags = merge(var.tags, {
    Domain = "BANKING"
  })
}