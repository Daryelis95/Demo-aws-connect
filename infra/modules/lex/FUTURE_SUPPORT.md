# Soporte Futuro: Gestión de Intents de Lex en Terraform

**Estado**: 🔴 No disponible aún (AWS Provider v5.100.0)  
**Blocker**: [hashicorp/terraform-provider-aws#33934](https://github.com/hashicorp/terraform-provider-aws/issues/33934)

---

## Qué Falta

El provider `hashicorp/aws` **NO tiene recursos** para gestionar:
- ✗ `aws_lexv2_bot_intent` (crear/actualizar intents)
- ✗ `aws_lexv2_bot_intent_slot` (slots)
- ✗ `aws_lexv2_bot_intent_confirmation_setting` (confirmaciones)
- ✗ `aws_lexv2_bot_locale` (aunque haya `aws_lexv2_bot_locale` en docs, no está disponible)

Sí existen:
- ✓ `aws_lex_v2_bot` (crear bot)
- ✓ `aws_lex_v2_bot_alias` (alias)
- ✓ `aws_lex_v2_bot_locale` (locale settings - limitado)

---

## Alternativas Hasta Que Terraform Agregue Soporte

### 1. **AWS CDK (Recomendado para DevOps)**
```typescript
// infra/lib/lex-banking-bot.ts
import * as lexmodels from 'aws-cdk-lib/aws-lexmodelsv2';

const bot = new lexmodels.CfnBot(this, 'BankingFraudBot', {
  // ...
});

const intent = new lexmodels.CfnIntent(this, 'ReportFraudIntent', {
  botId: bot.ref,
  intentName: 'ReportFraud',
  sampleUtterancesSetting: {
    active: true,
    sampleUtterances: [
      { sampleUtterance: { utterance: 'quiero reportar un fraude' } },
      { sampleUtterance: { utterance: 'hay fraude en mi cuenta' } },
      // ...
    ]
  }
});
```

**Pros**: Type-safe, versionable, integrado con IaC  
**Contras**: Requiere Node.js + TypeScript

---

### 2. **Terraform + Local Scripts (Actual)**
```hcl
# infra/modules/lex/main.tf

resource "null_resource" "create_intents" {
  provisioner "local-exec" {
    command = "python3 ${path.module}/../../../scripts/create_lex_intents.py"
    environment = {
      BOT_ID = aws_lexv2_bot.main.id
      REGION = var.region
      PROFILE = var.aws_profile
    }
  }
}
```

**Pros**: Mantiene Terraform como orquestador  
**Contras**: Acoplamiento a scripts, más frágil ante cambios

---

### 3. **boto3 Wrapper con SDKv2 (Actual)**
```python
# scripts/create_lex_intents.py
# (ya implementado en el proyecto)
```

**Pros**: Flexible, fácil de versionar  
**Contras**: Script externo, no idempotente si no se cuida bien

---

## Estructura Propuesta para Cuando Terraform lo Soporte

```hcl
# infra/modules/lex/main.tf

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50.0"  # Versión mínima que tenga soporte
    }
  }
}

# Bot principal
resource "aws_lexv2_bot" "banking_fraud" {
  name                        = "BankingFraudBot"
  description                 = "Bot para reportes de fraude bancario"
  type                        = "STANDARD"
  data_privacy                = jsonencode({ childDirected = false })
  idle_session_ttl_in_seconds = 900
  
  # Será necesario especificar roles
  role_arn = aws_iam_role.lex_bot_role.arn
}

# Locale (es-419)
resource "aws_lexv2_bot_locale" "es_419" {
  bot_id              = aws_lexv2_bot.banking_fraud.id
  locale_id           = "es_419"
  description         = "Español latinoamericano"
  n_lu_confidence_threshold = 0.4
}

# Intents
resource "aws_lexv2_bot_intent" "report_fraud" {
  bot_id    = aws_lexv2_bot.banking_fraud.id
  locale_id = aws_lexv2_bot_locale.es_419.locale_id
  
  intent_name = "ReportFraud"
  description = "Reportar fraude en cuenta"
  
  sample_utterances_setting = {
    active = true
    
    sample_utterances = [
      { utterance = "quiero reportar un fraude" },
      { utterance = "hay fraude en mi cuenta" },
      { utterance = "sospechos de fraude" },
      # ... más utterances
    ]
  }
  
  # Fulfillment
  fulfillment_code_hook {
    enabled = false  # Para V3, no hay Lambda en el camino crítico
  }
}

resource "aws_lexv2_bot_intent" "report_unauthorized" {
  bot_id    = aws_lexv2_bot.banking_fraud.id
  locale_id = aws_lexv2_bot_locale.es_419.locale_id
  
  intent_name = "ReportUnauthorized"
  description = "Movimiento no autorizado"
  
  sample_utterances_setting = {
    active = true
    
    sample_utterances = [
      { utterance = "hay un movimiento no autorizado" },
      { utterance = "no reconozco este cargo" },
      # ...
    ]
  }
}

# Aliases
resource "aws_lexv2_bot_alias" "sandbox_banking" {
  bot_id       = aws_lexv2_bot.banking_fraud.id
  alias_name   = "SandboxBanking"
  description  = "Alias de sandbox para pruebas"
  bot_version  = aws_lexv2_bot.banking_fraud.latest_bot_version
  
  # Credential handling (si se necesita)
  #conversation_logs = { /* config */ }
}

# Outputs
output "bot_id" {
  value = aws_lexv2_bot.banking_fraud.id
}

output "alias_id" {
  value = aws_lexv2_bot_alias.sandbox_banking.bot_alias_id
}

output "alias_arn" {
  value = "arn:aws:lex:${var.region}:${data.aws_caller_identity.current.account_id}:bot-alias/${aws_lexv2_bot.banking_fraud.id}/${aws_lexv2_bot_alias.sandbox_banking.bot_alias_id}"
}
```

---

## Variables (Estructura)

```hcl
# infra/modules/lex/variables.tf

variable "bot_name" {
  type        = string
  default     = "BankingFraudBot"
  description = "Nombre del bot Lex"
}

variable "locale_id" {
  type        = string
  default     = "es_419"
  description = "Locale (es_419, es_ES, en_US, etc)"
}

variable "intents" {
  type = map(object({
    description          = string
    sample_utterances    = list(string)
    confirmation_prompt  = optional(string)
    fulfillment_hook     = optional(bool)
  }))
  
  default = {
    ReportFraud = {
      description = "Reportar fraude"
      sample_utterances = [
        "quiero reportar un fraude",
        "hay fraude en mi cuenta",
        "sospechos de fraude",
        "reportar actividad fraudulenta",
      ]
      confirmation_prompt = null
      fulfillment_hook    = false
    }
    ReportUnauthorized = {
      description = "Movimiento no autorizado"
      sample_utterances = [
        "hay un movimiento no autorizado",
        "no reconozco este cargo",
        "no autorizo este movimiento",
      ]
      confirmation_prompt = null
      fulfillment_hook    = false
    }
    # ... más intents
  }
}
```

---

## Plan de Migración

### Fase 1: Monitoreo (Hoy)
- [ ] Seguir [issue #33934](https://github.com/hashicorp/terraform-provider-aws/issues/33934)
- [ ] Usar scripts Python como workaround (ya implementado)
- [ ] Documentar estado en `.kiro/lex-intents-specification.md`

### Fase 2: Soporte en Provider (Cuando AWS publique)
- [ ] Crear `infra/modules/lex/` con recursos `aws_lexv2_bot_intent`
- [ ] Migrar de scripts a Terraform
- [ ] Versionar bot automáticamente
- [ ] Alias con `depends_on` en la instancia de Connect

### Fase 3: Integración con CDK (Opcional)
- [ ] Si se adopta CDK en el proyecto, consolidar aquí
- [ ] Sincronizar estado entre Terraform + CDK

---

## Notas

1. **Versionado de Bot**: Lex versionea automáticamente cada compilación (`v1`, `v2`, ...). Terraform necesitaría `aws_lexv2_bot_version` para gestionarlas.

2. **Fulfillment**: Si en el futuro se requiere callback Lambda, se podría agregar:
   ```hcl
   fulfillment_code_hook {
     enabled      = true
     active       = true
     fulfillment_updates_specification = {
       active                     = true
       start_response             = "Procesando..."
       update_response            = "Aún procesando..."
       timeout_in_seconds         = 10
     }
   }
   ```

3. **Testing**: Agregar `awscc_lexmodelsv2_intent` del provider `hashicorp/awscc` (más reciente pero menos estable).

---

**Última actualización**: 2026-10-11  
**Mantenedor**: Team Infra  
**Status**: 🔴 Bloqueado por issue de Terraform
