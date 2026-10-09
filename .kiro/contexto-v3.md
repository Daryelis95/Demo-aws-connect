# Contexto V3 — Demo bancaria antifraude
> Resumen para retomar el trabajo en un nuevo chat.
> Proyecto: `connect-demo-infra` | Rama: `master` | Fecha: 08/10/2026

---

## Qué es este proyecto

Demo de Amazon Connect para un banco. El cliente llama, reporta un movimiento sospechoso, autoriza o rechaza el bloqueo de su tarjeta, y la llamada termina con un expediente abierto en Amazon Connect Cases visible para el agente.

Stack: Amazon Connect + Lex (BankingFraudBot) + Lambda (Python) + DynamoDB + Bedrock + Amazon Connect Cases.

Infraestructura gestionada con Terraform (`infra/`). Código Lambda en `src/tools/`.

---

## Qué se hizo hasta hoy

### Terraform — ya en el repo (`master`)

| Qué | Dónde |
|---|---|
| Export del flujo antifraude real de la consola (solo lectura) | `infra/modules/connect/flows/banking-v2.export.json` |
| Flujo V3 parametrizado con `templatefile()` | `infra/modules/connect/flows/banking-v3.json` |
| `contact_flow_logs_enabled = true` en la instancia Connect | `modules/connect/main.tf` |
| Nueva cola `FraudQueue` con prioridad 1 en el routing profile | `modules/connect/main.tf` |
| Recurso `banking_v3` con `count` (se activa con `enable_banking_v3_flow`) | `modules/connect/main.tf` |
| Asociación de Lambda `create-fraud-case` a la instancia Connect | `modules/connect/main.tf` |
| Variables V3 nuevas | `modules/connect/variables.tf` y `environments/sandbox/variables.tf` |
| `terraform.tfvars.example` con alias ARN del bot precargado y placeholders de Cases | `environments/sandbox/terraform.tfvars.example` |
| Fix: `bedrock_model_id` ahora se pasa al módulo lambda (antes no se pasaba) | `environments/sandbox/main.tf` |
| Documentación del plan completo V3 | `.kiro/v3-cases-fraude-bancario.md` |
| Log de actividades | `.kiro/daily-log.md` |

### Datos conocidos del sandbox

| Dato | Valor |
|---|---|
| Instance ID | `6198ee3d-76f0-4a24-8171-e50d802cBB71` |
| Account ID | `063103265536` |
| Región | `us-east-1` |
| Bot Lex | `BankingFraudBot` — botId `NXHHCKVHHM` |
| Alias Lex | `SandboxBanking` — aliasId `ZSII5DJKMX` |
| Bot Alias ARN | `arn:aws:lex:us-east-1:063103265536:bot-alias/NXHHCKVHHM/ZSII5DJKMX` |
| Voz TTS | `Mia` / `es-MX` |
| Idioma Lex | `es-419` |
| Cliente de prueba | `CUS-2001` / tarjeta `CARD-4455` / transacción sospechosa `TXN-9002` |
| BankingQueue ARN | `arn:aws:connect:us-east-1:063103265536:instance/.../queue/241a4498-...` |

---

## Qué falta — pendientes en orden

### 1. Consola AWS (hacer primero, sin esto el `terraform apply` no puede correr)

- [ ] Habilitar **Customer Profiles** en la instancia Connect si no está activo
- [ ] Crear perfil de prueba para `CUS-2001` con `AccountNumber = CUS-2001`
- [ ] Crear dominio **Amazon Connect Cases** `connect-demo-banking-sandbox-cases`
- [ ] Asociar el dominio Cases a la instancia (`CASES_DOMAIN`)
- [ ] Crear campos personalizados en Cases: `customerId`, `transactionId`, `cardReference`, `blockResult`, `blockedAt`, `consent`, `operationId`, `priority`, `contactId`
- [ ] Crear layout y plantilla **"Reporte de fraude bancario"** (estado Activo)
- [ ] Crear un caso manual de prueba y verificar que se ve en el workspace del agente
- [ ] Copiar todos los IDs obtenidos al archivo `terraform.tfvars`

```bash
# Comandos para obtener los IDs una vez creados
aws connectcases list-domains
aws connectcases list-templates --domain-id <ID>
aws connectcases list-fields    --domain-id <ID>
aws customer-profiles list-domains
```

### 2. Lambda `block_card/handler.py` — modificar

- [ ] Agregar parámetro `consent`: si no es `"true"` → devolver `blockResult="NOT_AUTHORIZED"` sin tocar DynamoDB
- [ ] Agregar campo `blockResult` en la respuesta: `BLOCKED`, `ALREADY_BLOCKED`, `FAILED`, `NOT_AUTHORIZED`
- [ ] Agregar campo `cardReference = "****" + last4`
- [ ] Agregar acción `getCardStatus` (solo lectura, para contingencia de timeout)
- [ ] Quitar `invoke_bedrock` del camino crítico (reemplazar por mensaje fijo)
- [ ] Guardar `operation_id` y `blocked_by_contact` en el `update_item` de DynamoDB
- [ ] Respuesta esperada:
```json
{
  "success": "true",
  "blockResult": "BLOCKED",
  "cardReference": "****4455",
  "previousStatus": "ACTIVE",
  "newStatus": "BLOCKED",
  "blockedAt": "2026-10-08T15:04:05Z",
  "errorCode": "",
  "message": "La tarjeta terminada en 4455 fue bloqueada."
}
```

### 3. Lambda `get_transactions/handler.py` — modificar

- [ ] Leer `cardStatus` del ítem `CUSTOMER#id / CARD#cardId` en DynamoDB (no del PROFILE con default `"ACTIVE"`)
- [ ] No registrar el evento completo en logs (evitar PII)
- [ ] Reemplazar `"error": f"...{exc}"` por `errorCode="DATABASE_ERROR"`
- [ ] Devolver `operationId = FRAUD-{customerId}-{transactionId}` y `cardReference = "****" + last4`
- [ ] Limitar `bedrockResponse` a ~500 caracteres o agregar variable `ENABLE_BEDROCK_SUMMARY`

### 4. Lambda nueva `src/tools/create_fraud_case/handler.py` — crear

Contrato de entrada (`Details.Parameters`):
`customerId`, `transactionId`, `cardReference`, `blockResult`, `consent`, `blockedAt`, `operationId`
`ContactId` e `InstanceARN` se leen de `Details.ContactData`.

Contrato de salida STRING_MAP:
`success`, `caseId`, `caseArn`, `caseCreated`, `contactLinked`, `errorCode`

Lógica principal:
1. Validar entrada
2. Registro en DynamoDB (`PK=CUSTOMER#id / SK=FRAUDOP#operationId`) para deduplicación — si ya existe y tiene `CASE_CREATED`, reutilizar el `caseId`
3. Resolver Customer Profile ARN con `SearchProfiles`
4. `CreateCase` con `clientToken` del ledger
5. `CreateRelatedItem` tipo Contact con el `contactArn`
6. Log estructurado con `event = case_created | case_reused | case_create_failed | contact_link_failed`

Variables de entorno necesarias: `CASES_DOMAIN_ID`, `CASES_TEMPLATE_ID`, `CASES_FIELD_IDS` (JSON), `CUSTOMER_PROFILES_DOMAIN`, `DYNAMODB_TABLE_NAME`

### 5. Terraform `infra/modules/iam/` — modificar

- [ ] Agregar rol IAM propio `create_fraud_case` con permisos mínimos:
  - `cases:CreateCase`, `cases:GetCase`, `cases:CreateRelatedItem`, `cases:SearchRelatedItems`
  - `profile:SearchProfiles`
  - `dynamodb:GetItem`, `dynamodb:PutItem`, `dynamodb:UpdateItem`
  - `logs:CreateLogStream`, `logs:PutLogEvents`
- [ ] Agregar `create-fraud-case` a la lista `connect_lambda_invoke`
- [ ] Nuevos outputs: `create_fraud_case_role_arn`, `create_fraud_case_role_name`

### 6. Terraform `infra/modules/lambda/` — modificar

- [ ] Agregar `create-fraud-case` a `local.tools` con `role_arn` propio y `extra_env` de Cases
- [ ] Modificar `aws_lambda_function.tool`: usar `try(each.value.role_arn, var.lambda_execution_role_arn)`
- [ ] Agregar variables: `cases_domain_id`, `cases_template_id`, `cases_field_ids`, `customer_profiles_domain_name`, `create_fraud_case_role_arn`
- [ ] Agregar output: `create_fraud_case_arn`

### 7. Terraform `infra/environments/sandbox/main.tf` — agregar

- [ ] Política inline `connect:DescribeContact` para el rol de `create-fraud-case`:
```hcl
resource "aws_iam_role_policy" "create_fraud_case_describe_contact" {
  name   = "${var.project_name}-${var.environment}-describe-contact"
  role   = module.iam.create_fraud_case_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["connect:DescribeContact"],
      Resource = "${module.connect.instance_arn}/contact/*" }]
  })
}
```

### 8. Terraform `infra/modules/observability/` — modificar

- [ ] Agregar `create-fraud-case` a `local.tool_functions` (alarma de errores + dashboard)
- [ ] Metric filters: `case_created`, `case_reused`, `case_create_failed`, `contact_link_failed`
- [ ] Alarma: `case_create_failed > 0` en 5 min → SNS

---

## Flujo V3 en palabras

```
Llamada entra
  → Logs + voz Mia (es-MX) + idioma Lex (es-419)
  → Lex detecta ReportFraud (1 reintento si no entiende)
  → Lambda get-transactions (customer_id dinámico)
  → Guardar atributos (transactionId, operationId, merchant, amount...)
  → Presentar cargo dinámico al cliente
  → Lex: ¿reconoces la compra?
      ConfirmYes → fin sin bloqueo
      ConfirmNo  → Lex: ¿autorizas bloquear la tarjeta?
          ConfirmYes → Lambda block-card (consent=true)
          ConfirmNo  → Guardar NOT_AUTHORIZED
  → Lambda create-fraud-case (siempre, con o sin bloqueo)
  → Guardar caseId
  → Prompt final con caseId si existe
  → Transferir a FraudQueue con contexto completo para el agente
```

## Checklist antes del `terraform apply`

- [ ] `terraform.tfvars` completado con IDs de Cases y Customer Profiles
- [ ] Módulos `iam`, `lambda` y `observability` actualizados (pendientes 5-8)
- [ ] `src/tools/create_fraud_case/handler.py` creado
- [ ] `block_card/handler.py` y `get_transactions/handler.py` modificados
- [ ] `terraform validate` sin errores
- [ ] `terraform plan` revisado: 0 destroy, 0 replace en recursos existentes
- [ ] Prueba manual del flujo V3 desde la consola antes de mover el número telefónico
