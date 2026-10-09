# Contexto V3 — Demo bancaria antifraude
> Resumen para retomar el trabajo en un nuevo chat.
> Proyecto: `connect-demo-infra` | Rama: `master` | Última actualización: `09/10/2026 — 20:40`

---

## Qué es este proyecto

Demo de Amazon Connect para un banco. El cliente llama o chatea, reporta un movimiento sospechoso, autoriza o rechaza el bloqueo de su tarjeta, y la llamada termina con un expediente abierto en Amazon Connect Cases visible para el agente.

Stack: Amazon Connect + Lex (BankingFraudBot) + Lambda (Python) + DynamoDB + Amazon Connect Cases + Customer Profiles.

Infraestructura gestionada con Terraform (`infra/`). Código Lambda en `src/tools/`.

---

## Datos del sandbox

| Dato | Valor |
|---|---|
| Instance ID | `6198ee3d-76f0-4a24-8171-e50d802c8871` |
| Instance ARN | `arn:aws:connect:us-east-1:063103265536:instance/6198ee3d-76f0-4a24-8171-e50d802c8871` |
| Account ID | `063103265536` |
| Región | `us-east-1` |
| AWS CLI profile | `sandbox` |
| Bot Lex | `BankingFraudBot` — botId `NXHHCKVHHM` |
| Alias Lex | `SandboxBanking` — aliasId `ZSII5DJKMX` |
| Bot Alias ARN | `arn:aws:lex:us-east-1:063103265536:bot-alias/NXHHCKVHHM/ZSII5DJKMX` |
| Voz TTS | `Mia` / `es-MX` |
| Idioma Lex | `es-419` |
| Contact Flow V3 ID | `b19c9caf-c23d-450a-8d14-92f374121442` |
| FraudQueue ID | `482b6530-19b5-42cd-8b6f-46b4fab07220` |
| BankingQueue ID | `241a4498-24dc-4bb4-8079-586586a94439` |
| RetailQueue ID | `14d00b6b-67df-4156-95bc-f421a749778b` |
| Cases Domain ID | `0c507c5e-02b9-4f30-82f9-d9cc20fac1d8` |
| Cases Template ID | `42cdb67b-8256-4656-80e6-637cb5e8fe34` |
| Cases field: customerId | `a7f0ea33-f713-4889-a76e-04e40ea97ef0` |
| Cases field: transactionId | `e8281ec5-970f-4d5d-863c-56b635256cba` |
| Cases field: cardReference | `1b37058d-0826-4145-beb3-bf1392ead7bf` |
| Cases field: blockResult | `55d8e18f-37f6-4866-a0a5-d1d2a00403e9` |
| Cases field: blockedAt | `e256b5f2-162d-4f3c-a014-3935d0981932` |
| Cases field: consent | `52729c3b-3027-4bbe-a126-1136f2f83196` |
| Cases field: operationId | `ec1a0b44-7e92-40a5-811c-4514025c688b` |
| Cases field: priority | `e935fdd5-e770-4fd1-bf76-27c832b5cb83` |
| Cases field: contactId | `5198411d-e7d8-4c11-a018-95ee78f7ebcf` |
| Customer Profiles Domain | `connect-demo-banking-sandbox` |
| Default customer queue flow ID | `d1d1413b-40e5-422a-adc2-90aebe5cbf26` |
| Fraud customer queue flow ID | `f567b1b8-c8b9-4273-a9ae-b5082289ce0a` |

---

## Clientes de prueba en DynamoDB

El ID se ingresa **solo con números** — la Lambda agrega el prefijo `CUS-` automáticamente.

| Tipear | Customer ID real | Nombre | Tarjeta | Cargo sospechoso | Notas |
|---|---|---|---|---|---|
| `2001` | CUS-2001 | Martín Fernández | ****4455 | $850 Electronics Store | Cliente original del seed |
| `3001` | CUS-3001 | Ana Torres | ****1111 | $1,200 Apple Store Miami | |
| `3002` | CUS-3002 | Carlos Mendoza | ****2222 | $3,500 Luxury Travel Agency | |
| `3003` | CUS-3003 | María Rodríguez | ****3333 | $220 Amazon Marketplace | |
| `3004` | CUS-3004 | Jorge Vázquez | ****4444 | $750 International Wire | ← tarjeta ya BLOQUEADA |
| `3005` | CUS-3005 | Laura Castillo | ****5555 | $890 Electronics Online Store | |

---

## Estado actual — qué está implementado

### ✅ Infraestructura AWS (consola/CLI)
- Customer Profiles habilitado, dominio `connect-demo-banking-sandbox`
- Perfil de prueba CUS-2001 creado en Customer Profiles
- Dominio Cases `connect-demo-banking-sandbox-cases` creado y asociado a la instancia
- 9 campos personalizados creados en Cases
- Plantilla "Reporte de fraude bancario" creada (estado Active)
- `terraform.tfvars` completado con todos los IDs
- Default customer queue actualizado con mensajes en español

### ✅ Código Lambda (`src/tools/`)
- `block_card/handler.py` — V3: consent check, blockResult enum, cardReference, getCardStatus, sin Bedrock en camino crítico, guarda operationId en DynamoDB
- `get_transactions/handler.py` — V3: lee cardStatus de CARD# en DynamoDB, operationId generado, cardReference enmascarado, normaliza customer_id (agrega `CUS-` si recibe solo número), logs sin PII, ENABLE_BEDROCK_SUMMARY variable
- `create_fraud_case/handler.py` — nuevo: deduplicación con FRAUDOP# en DynamoDB, SearchProfiles, CreateCase con clientToken idempotente, CreateRelatedItem para vincular contacto

### ✅ Terraform (`infra/`)
- `modules/lambda/main.tf` — create-fraud-case en local.tools con extra_env, rol propio, env vars de Cases
- `modules/lambda/variables.tf` — 5 variables nuevas (cases_*, customer_profiles_*, create_fraud_case_role_arn)
- `modules/lambda/outputs.tf` — output create_fraud_case_arn
- `modules/iam/main.tf` — rol create_fraud_case con 4 políticas mínimas, create-fraud-case en connect_lambda_invoke
- `modules/iam/variables.tf` y `outputs.tf` — variables y outputs del nuevo rol
- `modules/observability/main.tf` — create-fraud-case en tool_functions, 4 metric filters, alarma case_create_failed
- `modules/connect/main.tf` — security profile corregido (permisos válidos), fraud_queue_flow customer queue flow
- `modules/connect/flows/banking-v3.json` — flujo V3 completo con menú DTMF, captura de ID numérico, validaciones, confirmaciones DTMF
- `modules/connect/flows/fraud_customer_queue.json` — mensajes de espera en español
- `environments/sandbox/main.tf` — política inline DescribeContact, depends_on observability→lambda
- `environments/sandbox/variables.tf` — cases_field_ids como string, variables V3
- `environments/sandbox/terraform.tfvars` — todos los IDs del sandbox completados

### ✅ Scripts (`scripts/`)
- `seed_data.sh` — datos originales (CUS-1001 retail, CUS-2001 banca)
- `seed_fraud_clients.sh` — 5 clientes nuevos con movimientos sospechosos (CUS-3001 a CUS-3005)
- `create_cases_fields.sh` — crea los 9 campos en el dominio Cases
- `create_cases_template.sh` — crea la plantilla con los campos requeridos

---

## Flujo V3 actual (banking-v3.json)

```
Llamada/Chat entra
  → Logs + voz Mia (es-MX) + idioma es-419
  → Verificar canal
      VOICE → Menú DTMF: "Presione 1 fraude / 2 agente" (2 intentos)
      CHAT  → Lex directamente
  → Lex: "¿Deseas reportar un movimiento no reconocido?" (2 intentos → agente)
  → Solicitar ID cliente: "Ingresa tu número" (solo dígitos, ej: 2001) — 30s
  → Lambda get-transactions (customer_id normalizado a CUS-XXXX)
      Si cliente no existe → reintento → agente
      Si no hay transacción sospechosa → mensaje → agente
  → Presentar cargo: "$MONTO en MERCHANT"
  → DTMF: ¿Reconoces? 1=Sí / 0=No (2 intentos)
      1=Sí → "No bloquearemos tu tarjeta. Gracias." → Fin
      0=No → DTMF: ¿Bloquear tarjeta ****XXXX? 1=Sí / 0=No (2 intentos)
          1=Sí → Lambda block-card (consent=true)
          0=No → Guardar NOT_AUTHORIZED
  → Lambda create-fraud-case (siempre)
  → Mensaje con caseId si se creó
  → Transferir a FraudQueue (agente ve todo el contexto)
```

---

## Pendientes

### 🔴 Crítico — debe hacerse antes de considerar el flujo completo

- [x] **Verificar que el caso se ve en el workspace del agente** — ✅ Resuelto el 09/10/2026. Dos bugs corregidos y desplegados:
  1. **`handler.py`** — campo `title` no se incluía en `fields[]` → `ValidationException`. Fix: `build_case_fields()` ahora inserta `{"id":"title",...}` siempre.
  2. **`modules/iam/main.tf`** — política `cases-policy` solo tenía `domain/<id>/*` → `AccessDeniedException` en `CreateCase`. Fix: `Resource` ahora incluye también el ARN base del dominio.
  - Prueba unitaria OK: `caseId dc8f656b-721d-3e25-8683-bc62ddbee01a`, `status open`, visible en `search-cases`.
  - `contactLinked: false` en test unitario es esperado (ContactId inventado). En el flujo real de Connect será `true`.
  - Permisos del agente confirmados: `Cases.Create/Edit/View` en `connect-demo-banking-sandbox-agent-profile`.

- [x] **Redesplegar `get_transactions` y `block_card`** — ✅ Verificado el 09/10/2026. Ambas Lambdas tienen código V3 desplegado:
  - `block-card`: `LastModified 2026-10-09T19:17` — tiene `consent`, `blockResult`, `cardReference`, `getCardStatus`, sin Bedrock en camino crítico.
  - `get-transactions`: `LastModified 2026-10-09T18:13` — tiene `operationId`, `cardReference`, `ENABLE_BEDROCK_SUMMARY`, normalización `CUS-` automática.

### 🟡 Importante — mejoras pendientes

- [x] **Habilitar Cases en el Agent Workspace** — ✅ Verificado el 09/10/2026. Agent applications → Case templates muestra la plantilla "Reporte de fraude bancario" en estado Active. El widget de Cases está operativo para el agente demo.
- [ ] **Proteger el estado de Terraform** — el backend S3 está comentado en `versions.tf`. Activarlo para que el `terraform.tfstate` no quede local:
  ```hcl
  # Descomentar en infra/environments/sandbox/versions.tf
  backend "s3" {
    bucket         = "connect-demo-tfstate"
    key            = "sandbox/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "connect-demo-tfstate-lock"
    encrypt        = true
  }
  ```
- [x] **Crear perfiles en Customer Profiles para los clientes nuevos** (CUS-3001 a CUS-3005) — ✅ Creados el 09/10/2026. SearchProfiles por `_account` los encuentra correctamente.

  | Customer ID | ProfileId | Nombre |
  |---|---|---|
  | CUS-3001 | `5987135f636b468da873d39101865795` | Ana Torres |
  | CUS-3002 | `2ccf35479ecb44049aa8511729c75944` | Carlos Mendoza |
  | CUS-3003 | `0a07fc1448cd463cbb535c45444b8662` | María Rodríguez |
  | CUS-3004 | `0a83546194fa49a7bceba1450cdbeafb` | Jorge Vázquez |
  | CUS-3005 | `cc8c94d6ecc540b2856559fec144eca3` | Laura Castillo |
- [x] **Métricas funcionales** — ✅ Verificado el 09/10/2026. Los 4 metric filters están activos en `connect-demo-banking-sandbox/FraudCase` y registraron datos reales durante las pruebas de hoy: `case_created=1`, `case_create_failed=5` (bugs pre-fix), `contact_link_failed=1` (ContactId de prueba). Alarma `case-create-failed` en estado OK.

### 🟢 Opcional / post-demo

- [x] Mover el número telefónico al flujo V3 — ✅ Realizado el 09/10/2026
- [ ] Agregar más intents a Lex para manejar variaciones de "quiero reportar fraude"
- [ ] Probar el flujo con llamada de voz real (actualmente solo probado en chat)

---

## Comandos útiles de referencia

```bash
# Actualizar flujo V3 directamente (sin terraform apply)
cd /Users/daryelispinate/Desktop/proyectosIVCISA/connect-demo-infra
python3 -c "
import json
with open('infra/modules/connect/flows/banking-v3.json') as f:
    raw = f.read()
content = raw\
  .replace('\${lex_bot_alias_arn}', 'arn:aws:lex:us-east-1:063103265536:bot-alias/NXHHCKVHHM/ZSII5DJKMX')\
  .replace('\${get_transactions_lambda_arn}', 'arn:aws:lambda:us-east-1:063103265536:function:connect-demo-banking-sandbox-get-transactions')\
  .replace('\${block_card_lambda_arn}', 'arn:aws:lambda:us-east-1:063103265536:function:connect-demo-banking-sandbox-block-card')\
  .replace('\${create_fraud_case_lambda_arn}', 'arn:aws:lambda:us-east-1:063103265536:function:connect-demo-banking-sandbox-create-fraud-case')\
  .replace('\${fraud_queue_flow_id}', 'f567b1b8-c8b9-4273-a9ae-b5082289ce0a')\
  .replace('\${fraud_queue_id}', '482b6530-19b5-42cd-8b6f-46b4fab07220')
with open('/tmp/banking-v3-expanded.json', 'w') as f: f.write(content)
print('OK')
" && aws connect update-contact-flow-content \
  --instance-id 6198ee3d-76f0-4a24-8171-e50d802c8871 \
  --contact-flow-id b19c9caf-c23d-450a-8d14-92f374121442 \
  --content "\$(cat /tmp/banking-v3-expanded.json)" \
  --region us-east-1 --profile sandbox && echo "✅ Flujo actualizado"

# Verificar casos creados
aws connectcases search-cases \
  --domain-id 0c507c5e-02b9-4f30-82f9-d9cc20fac1d8 \
  --fields '[{"id":"title"}]' \
  --region us-east-1 --profile sandbox

# Redesplegar una Lambda específica
cd infra/environments/sandbox && export AWS_PROFILE=sandbox
rm -f ../../modules/lambda/.build/get-transactions.zip
terraform plan -target='module.lambda.aws_lambda_function.tool["get-transactions"]' -out=tfplan.out
terraform apply tfplan.out
```
