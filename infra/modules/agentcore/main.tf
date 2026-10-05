# ------------------------------------------------------------------
# NOTA DE SOPORTE TERRAFORM
#
# A la fecha de creación de este módulo, Bedrock AgentCore Runtime y
# AgentCore Gateway son servicios recientes. El provider hashicorp/aws
# >= 5.60 incluye soporte para aws_bedrockagent_agent y recursos
# relacionados. Sin embargo, algunos recursos avanzados de AgentCore
# (como el Gateway propiamente dicho) pueden requerir CloudFormation
# o AWS CLI hasta que el provider los soporte completamente.
#
# Recursos Terraform disponibles utilizados:
#   - aws_bedrockagent_agent          (Agente Bedrock)
#   - aws_bedrockagent_agent_alias    (Alias del agente)
#   - aws_bedrockagent_agent_action_group (Grupo de acciones / tools)
#
# Recurso que puede requerir validación manual:
#   - AgentCore Gateway → ver cloudformation/agentcore-gateway.yaml
# ------------------------------------------------------------------

locals {
  prefix     = "${var.project_name}-${var.environment}"
  agent_name = "${local.prefix}-agent"
}

# ------------------------------------------------------------------
# Instrucción del sistema (prompt base del agente)
# ------------------------------------------------------------------
locals {
  agent_instruction = <<-EOT
    Eres un asistente virtual de atención al cliente que opera en dos dominios de negocio:
    RETAIL y BANCA. Debes identificar el dominio activo desde el contexto de la sesión.

    REGLAS GENERALES:
    - Habla siempre en español.
    - Sé conciso, claro y profesional.
    - Nunca inventes identificadores de clientes, pedidos, tarjetas o transacciones.
    - Solo ejecuta acciones sobre datos recuperados de las herramientas disponibles
      o proporcionados explícitamente por el usuario.
    - Antes de ejecutar cualquier acción que modifique estado (bloquear tarjeta,
      cambiar dirección), solicita confirmación explícita del usuario.
    - Si el usuario solicita hablar con un humano, confirma la transferencia y
      proporciona un resumen del contexto de la conversación.

    DOMINIO RETAIL:
    - Usa get_order para consultar el estado de un pedido.
    - Usa change_delivery_address para actualizar la dirección de entrega.
    - Informa siempre el estado, motivo de retraso y nueva fecha estimada.

    DOMINIO BANCA:
    - Usa get_transactions para consultar movimientos recientes.
    - Si hay transacciones sospechosas, preséntaselas al usuario y pregunta
      si las reconoce.
    - Si el usuario no reconoce una transacción, ofrece bloquear la tarjeta.
    - Usa block_card solo después de confirmación explícita del usuario.
    - Nunca registres ni repitas números completos de tarjetas.
  EOT
}

# ------------------------------------------------------------------
# Agente Bedrock
# ------------------------------------------------------------------
resource "aws_bedrockagent_agent" "main" {
  agent_name              = local.agent_name
  description             = var.agent_description
  agent_resource_role_arn = var.agentcore_execution_role_arn
  foundation_model        = var.bedrock_model_id
  instruction             = local.agent_instruction
  idle_session_ttl_in_seconds = var.idle_session_ttl_seconds

  tags = merge(var.tags, {
    Name = local.agent_name
  })
}

# ------------------------------------------------------------------
# Grupo de acciones — Retail tools
# ------------------------------------------------------------------
resource "aws_bedrockagent_agent_action_group" "retail" {
  agent_id          = aws_bedrockagent_agent.main.id
  agent_version     = "DRAFT"
  action_group_name = "RetailTools"
  description       = "Herramientas para el dominio Retail: consulta y modificación de pedidos."

  action_group_executor {
    lambda = var.get_order_lambda_arn
  }

  api_schema {
    payload = jsonencode({
      openapi = "3.0.0"
      info = {
        title   = "Retail Tools API"
        version = "1.0.0"
      }
      paths = {
        "/get_order" = {
          post = {
            summary     = "Consulta el estado de un pedido."
            operationId = "get_order"
            requestBody = {
              required = true
              content = {
                "application/json" = {
                  schema = {
                    type     = "object"
                    required = ["order_id"]
                    properties = {
                      order_id = {
                        type        = "string"
                        description = "Identificador único del pedido (ej: ORD-1001)."
                      }
                    }
                  }
                }
              }
            }
            responses = {
              "200" = {
                description = "Estado del pedido."
                content = {
                  "application/json" = {
                    schema = { type = "object" }
                  }
                }
              }
            }
          }
        }
        "/change_delivery_address" = {
          post = {
            summary     = "Actualiza la dirección de entrega de un pedido."
            operationId = "change_delivery_address"
            requestBody = {
              required = true
              content = {
                "application/json" = {
                  schema = {
                    type     = "object"
                    required = ["order_id", "new_address"]
                    properties = {
                      order_id = {
                        type        = "string"
                        description = "Identificador único del pedido."
                      }
                      new_address = {
                        type        = "string"
                        description = "Nueva dirección de entrega."
                      }
                    }
                  }
                }
              }
            }
            responses = {
              "200" = {
                description = "Confirmación de actualización."
                content = {
                  "application/json" = {
                    schema = { type = "object" }
                  }
                }
              }
            }
          }
        }
      }
    })
  }
}

# ------------------------------------------------------------------
# Grupo de acciones — Banca tools
# ------------------------------------------------------------------
resource "aws_bedrockagent_agent_action_group" "banking" {
  agent_id          = aws_bedrockagent_agent.main.id
  agent_version     = "DRAFT"
  action_group_name = "BankingTools"
  description       = "Herramientas para el dominio Banca: transacciones y bloqueo de tarjeta."

  action_group_executor {
    lambda = var.get_transactions_lambda_arn
  }

  api_schema {
    payload = jsonencode({
      openapi = "3.0.0"
      info = {
        title   = "Banking Tools API"
        version = "1.0.0"
      }
      paths = {
        "/get_transactions" = {
          post = {
            summary     = "Consulta los movimientos recientes de un cliente."
            operationId = "get_transactions"
            requestBody = {
              required = true
              content = {
                "application/json" = {
                  schema = {
                    type     = "object"
                    required = ["customer_id"]
                    properties = {
                      customer_id = {
                        type        = "string"
                        description = "Identificador único del cliente (ej: CUS-2001)."
                      }
                    }
                  }
                }
              }
            }
            responses = {
              "200" = {
                description = "Lista de movimientos recientes."
                content = {
                  "application/json" = {
                    schema = { type = "object" }
                  }
                }
              }
            }
          }
        }
        "/block_card" = {
          post = {
            summary     = "Bloquea una tarjeta bancaria."
            operationId = "block_card"
            requestBody = {
              required = true
              content = {
                "application/json" = {
                  schema = {
                    type     = "object"
                    required = ["card_id"]
                    properties = {
                      card_id = {
                        type        = "string"
                        description = "Identificador de la tarjeta (ej: CARD-4455)."
                      }
                    }
                  }
                }
              }
            }
            responses = {
              "200" = {
                description = "Confirmación de bloqueo."
                content = {
                  "application/json" = {
                    schema = { type = "object" }
                  }
                }
              }
            }
          }
        }
      }
    })
  }
}

# ------------------------------------------------------------------
# Alias del agente — apunta a la versión DRAFT para sandbox
# ------------------------------------------------------------------
resource "aws_bedrockagent_agent_alias" "sandbox" {
  agent_id         = aws_bedrockagent_agent.main.id
  agent_alias_name = "${local.prefix}-alias"
  description      = "Alias de sandbox para el agente de la demo Connect."

  tags = var.tags

  depends_on = [
    aws_bedrockagent_agent_action_group.retail,
    aws_bedrockagent_agent_action_group.banking
  ]
}
