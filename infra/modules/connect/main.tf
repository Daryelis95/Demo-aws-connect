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
  identity_management_type       = var.identity_management_type
  inbound_calls_enabled          = var.inbound_calls_enabled
  outbound_calls_enabled         = var.outbound_calls_enabled
  instance_alias                 = var.connect_instance_alias
  contact_flow_logs_enabled      = true   # V3: habilita logs de flujo en CloudWatch

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

# V3: asociar Lambda de create-fraud-case
resource "aws_connect_lambda_function_association" "create_fraud_case" {
  instance_id  = aws_connect_instance.main.id
  function_arn = var.create_fraud_case_lambda_arn
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
# V3: se agregan permisos de Cases y Customer Profiles
# Nota: los nombres API exactos se obtienen con:
#   aws connect list-security-profile-permissions \
#     --instance-id <id> --security-profile-id <sp-id>
# Si el plan muestra cambios inesperados, comparar contra la consola.
# ------------------------------------------------------------------
resource "aws_connect_security_profile" "agent" {
  instance_id = aws_connect_instance.main.id
  name        = "${local.prefix}-agent-profile"
  description = "Perfil de seguridad para agentes de la demo (Retail + Banca + Cases V3)."

  permissions = [
    # Acceso básico
    "BasicAgentAccess",
    "OutboundCallAccess",
    # Cases — ver, editar y crear
    "Cases.View",
    "Cases.Edit",
    "Cases.Create",
    # Historial de auditoría de Cases
    "Cases.AuditHistory.View",
    # Customer Profiles — ver
    "CustomerProfiles.View",
    # Ver colas, usuarios y quick-connects (necesario para asignar casos)
    "Queue.View",
    "User.View",
    "QuickConnect.View"
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
# Cola Banca (fallback y flujos legacy)
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
# V3: Cola de Fraude — destino del flujo banking-v3
# Prioridad 1 en el routing profile (por delante de BankingQueue)
# ------------------------------------------------------------------
resource "aws_connect_queue" "fraud" {
  instance_id           = aws_connect_instance.main.id
  name                  = var.fraud_queue_name
  description           = "Cola de alta prioridad para reportes de fraude bancario (V3)."
  hours_of_operation_id = aws_connect_hours_of_operation.all_day.hours_of_operation_id

  tags = merge(var.tags, {
    Domain   = "BANKING"
    UseCase  = "FRAUD_V3"
  })
}

# ------------------------------------------------------------------
# Routing Profile (Retail + Banca + Fraude)
# ------------------------------------------------------------------
resource "aws_connect_routing_profile" "main" {
  instance_id               = aws_connect_instance.main.id
  name                      = "${local.prefix}-routing-profile"
  description               = "Routing profile compartido para Retail, Banca y Fraude."
  default_outbound_queue_id = aws_connect_queue.retail.queue_id

  media_concurrencies {
    channel     = "VOICE"
    concurrency = 1
  }

  media_concurrencies {
    channel     = "CHAT"
    concurrency = 3
  }

  # Fraude: prioridad 1 — atiende antes que Banca y Retail
  queue_configs {
    channel  = "VOICE"
    delay    = 0
    priority = 1
    queue_id = aws_connect_queue.fraud.queue_id
  }

  queue_configs {
    channel  = "VOICE"
    delay    = 0
    priority = 2
    queue_id = aws_connect_queue.banking.queue_id
  }

  queue_configs {
    channel  = "VOICE"
    delay    = 0
    priority = 3
    queue_id = aws_connect_queue.retail.queue_id
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
# Contact Flow — Banca (original, no se toca)
# Sigue activo mientras el número esté apuntando a él.
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
    Domain  = "BANKING"
    Version = "v1"
  })
}

# ------------------------------------------------------------------
# V3: Contact Flow — Banca V3 con Amazon Connect Cases
#
# Se crea como recurso nuevo y en paralelo al flujo original.
# El número telefónico se mueve a este flujo desde la consola
# SOLO después de superar las pruebas de aceptación.
#
# Para desactivarlo sin destruir el recurso:
#   enable_banking_v3_flow = false  →  count = 0
# ------------------------------------------------------------------
resource "aws_connect_contact_flow" "banking_v3" {
  count = var.enable_banking_v3_flow ? 1 : 0

  instance_id = aws_connect_instance.main.id
  name        = "${local.prefix}-banking-flow-v3"
  description = "Contact flow V3: fraude bancario con expediente en Amazon Connect Cases."
  type        = "CONTACT_FLOW"

  content = templatefile("${path.module}/flows/banking-v3.json", {
    lex_bot_alias_arn            = var.banking_lex_bot_alias_arn
    get_transactions_lambda_arn  = var.get_transactions_lambda_arn
    block_card_lambda_arn        = var.block_card_lambda_arn
    create_fraud_case_lambda_arn = var.create_fraud_case_lambda_arn
    fraud_queue_id               = aws_connect_queue.fraud.queue_id
  })

  tags = merge(var.tags, {
    Domain  = "BANKING"
    Version = "v3"
    UseCase = "FRAUD_CASES"
  })
}
