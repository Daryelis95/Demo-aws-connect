# CLI Commands Log — Demo bancaria antifraude
> Registro de todos los comandos AWS CLI ejecutados en este proyecto.
> Cada entrada incluye: qué hace, cuándo se ejecutó y el resultado obtenido.
> Proyecto: `connect-demo-infra` | Account: `063103265536` | Región: `us-east-1`

---

## Convenciones

- `--profile sandbox` → profile AWS configurado localmente para el account del sandbox
- Los IDs reales se registran en la sección **Datos conocidos** de `contexto-v3.md`
- Los comandos de solo lectura (verificación) se marcan con 🔍
- Los comandos que crean o modifican recursos se marcan con 🔧

---

## 09/10/2026

---

### 🔧 Crear perfil de cliente en Customer Profiles

**Por qué:** La Lambda `create_fraud_case` necesita resolver el ARN del perfil del cliente usando `SearchProfiles`. Sin un perfil existente para `CUS-2001`, la Lambda fallará al intentar buscar el cliente durante la llamada.

**Contexto:** Customer Profiles es el servicio de AWS que identifica al cliente durante una llamada en Amazon Connect. El campo `account_number` es la clave de búsqueda que usará la Lambda.

```bash
aws customer-profiles create-profile \
  --domain-name connect-demo-banking-sandbox \
  --account-number "CUS-2001" \
  --first-name "Martín" \
  --last-name "Fernández" \
  --region us-east-1 \
  --profile sandbox
```

**Resultado:** Perfil creado exitosamente para el cliente de prueba `CUS-2001 / Martín Fernández`.

---

### 🔧 Crear dominio de Amazon Connect Cases

**Por qué:** Amazon Connect Cases requiere un dominio propio para almacenar los casos (expedientes) de fraude. Sin el dominio, no es posible crear ni consultar casos desde la Lambda ni desde el workspace del agente.

**Contexto:** Un dominio de Cases es un contenedor lógico que agrupa todos los casos, campos, plantillas y layouts de una instancia Connect. Solo se puede tener un dominio asociado por instancia.

```bash
aws connectcases create-domain \
  --name connect-demo-banking-sandbox-cases \
  --region us-east-1 \
  --profile sandbox
```

**Resultado:**
```json
{
    "domainArn": "arn:aws:cases:us-east-1:063103265536:domain/0c507c5e-02b9-4f30-82f9-d9cc20fac1d8",
    "domainId": "0c507c5e-02b9-4f30-82f9-d9cc20fac1d8",
    "domainStatus": "ACTIVE"
}
```

---

### 🔧 Asociar el dominio Cases a la instancia Connect

**Por qué:** Crear el dominio no es suficiente — hay que asociarlo explícitamente a la instancia de Amazon Connect para que el workspace del agente pueda ver los casos y para que las APIs de Cases puedan vincularse a los contactos de Connect.

**Contexto:** La asociación se hace mediante una "integration association" de tipo `CASES_DOMAIN`. Una instancia Connect solo puede tener un dominio de Cases asociado a la vez.

```bash
aws connect create-integration-association \
  --instance-id 6198ee3d-76f0-4a24-8171-e50d802c8871 \
  --integration-type CASES_DOMAIN \
  --integration-arn arn:aws:cases:us-east-1:063103265536:domain/0c507c5e-02b9-4f30-82f9-d9cc20fac1d8 \
  --region us-east-1 \
  --profile sandbox
```

**Resultado:**
```json
{
    "IntegrationAssociationId": "cd69e97a-e21e-4ebb-a5aa-17e697e6bab3",
    "IntegrationAssociationArn": "arn:aws:connect:us-east-1:063103265536:instance/6198ee3d-76f0-4a24-8171-e50d802c8871/integration-association/cd69e97a-e21e-4ebb-a5aa-17e697e6bab3"
}
```

---

### 🔧 Crear campos personalizados en el dominio Cases

**Por qué:** Los casos de fraude necesitan campos específicos del negocio que no existen por defecto en Cases (como `transactionId`, `blockResult`, `cardReference`, etc.). Estos campos se usan en la plantilla y son los que la Lambda `create_fraud_case` llena al abrir un expediente.

**Contexto:** Se usa el script `scripts/create_cases_fields.sh` que crea los 9 campos de una sola vez. Los IDs generados deben guardarse en `terraform.tfvars` como `cases_field_ids` (JSON).

```bash
bash scripts/create_cases_fields.sh
```

**Campos creados:**
| Campo | Tipo | Descripción |
|---|---|---|
| `customerId` | Text | ID del cliente que reporta el fraude |
| `transactionId` | Text | ID de la transacción sospechosa |
| `cardReference` | Text | Referencia enmascarada (ej: ****4455) |
| `blockResult` | Text | Resultado: BLOCKED, ALREADY_BLOCKED, FAILED, NOT_AUTHORIZED |
| `blockedAt` | Text | Timestamp ISO 8601 del bloqueo |
| `consent` | Text | Consentimiento del cliente: true o false |
| `operationId` | Text | ID único (ej: FRAUD-CUS-2001-TXN-9002) |
| `priority` | Text | Prioridad: HIGH, MEDIUM, LOW |
| `contactId` | Text | ID del contacto Connect asociado al caso |

**Resultado:**
| Campo | Field ID |
|---|---|
| `customerId` | `a7f0ea33-f713-4889-a76e-04e40ea97ef0` |
| `transactionId` | `e8281ec5-970f-4d5d-863c-56b635256cba` |
| `cardReference` | `1b37058d-0826-4145-beb3-bf1392ead7bf` |
| `blockResult` | `55d8e18f-37f6-4866-a0a5-d1d2a00403e9` |
| `blockedAt` | `e256b5f2-162d-4f3c-a014-3935d0981932` |
| `consent` | `52729c3b-3027-4bbe-a126-1136f2f83196` |
| `operationId` | `ec1a0b44-7e92-40a5-811c-4514025c688b` |
| `priority` | `e935fdd5-e770-4fd1-bf76-27c832b5cb83` |
| `contactId` | `5198411d-e7d8-4c11-a018-95ee78f7ebcf` |

`cases_field_ids` limpio para `terraform.tfvars`:
```
cases_field_ids = '{"customerId":"a7f0ea33-f713-4889-a76e-04e40ea97ef0","transactionId":"e8281ec5-970f-4d5d-863c-56b635256cba","cardReference":"1b37058d-0826-4145-beb3-bf1392ead7bf","blockResult":"55d8e18f-37f6-4866-a0a5-d1d2a00403e9","blockedAt":"e256b5f2-162d-4f3c-a014-3935d0981932","consent":"52729c3b-3027-4bbe-a126-1136f2f83196","operationId":"ec1a0b44-7e92-40a5-811c-4514025c688b","priority":"e935fdd5-e770-4fd1-bf76-27c832b5cb83","contactId":"5198411d-e7d8-4c11-a018-95ee78f7ebcf"}'
```

---

## Comandos de verificación útiles 🔍

```bash
# Listar dominios de Cases
aws connectcases list-domains \
  --region us-east-1 --profile sandbox

# Listar campos del dominio
aws connectcases list-fields \
  --domain-id 0c507c5e-02b9-4f30-82f9-d9cc20fac1d8 \
  --region us-east-1 --profile sandbox

# Listar plantillas del dominio
aws connectcases list-templates \
  --domain-id 0c507c5e-02b9-4f30-82f9-d9cc20fac1d8 \
  --region us-east-1 --profile sandbox

# Listar dominios de Customer Profiles
aws customer-profiles list-domains \
  --region us-east-1 --profile sandbox

# Buscar perfil CUS-2001
aws customer-profiles search-profiles \
  --domain-name connect-demo-banking-sandbox \
  --key-name _account \
  --values "CUS-2001" \
  --region us-east-1 --profile sandbox

# Verificar integraciones de la instancia Connect
aws connect list-integration-associations \
  --instance-id 6198ee3d-76f0-4a24-8171-e50d802c8871 \
  --region us-east-1 --profile sandbox

# Verificar identidad/credenciales activas
aws sts get-caller-identity --profile sandbox
```

---

### 🔧 Crear plantilla "Reporte de fraude bancario" en Cases

**Por qué:** La Lambda `create_fraud_case` necesita un `templateId` para llamar a `CreateCase`. La plantilla define la estructura del expediente que verá el agente en su workspace: qué campos son requeridos, cómo se organiza la información del fraude.

**Contexto:** Se usa el script `scripts/create_cases_template.sh` que tiene los field_ids ya cargados. Los campos requeridos en la plantilla son `customerId`, `transactionId` y `blockResult` — los mínimos que el agente necesita para gestionar el caso.

```bash
bash scripts/create_cases_template.sh
```

**Resultado:**
```
templateId  = 42cdb67b-8256-4656-80e6-637cb5e8fe34
templateArn = arn:aws:cases:us-east-1:063103265536:domain/0c507c5e-02b9-4f30-82f9-d9cc20fac1d8/template/42cdb67b-8256-4656-80e6-637cb5e8fe34
```

**Líneas para `terraform.tfvars`:**
```
cases_domain_id               = "0c507c5e-02b9-4f30-82f9-d9cc20fac1d8"
cases_template_id             = "42cdb67b-8256-4656-80e6-637cb5e8fe34"
cases_field_ids               = '{"customerId":"a7f0ea33-f713-4889-a76e-04e40ea97ef0","transactionId":"e8281ec5-970f-4d5d-863c-56b635256cba","cardReference":"1b37058d-0826-4145-beb3-bf1392ead7bf","blockResult":"55d8e18f-37f6-4866-a0a5-d1d2a00403e9","blockedAt":"e256b5f2-162d-4f3c-a014-3935d0981932","consent":"52729c3b-3027-4bbe-a126-1136f2f83196","operationId":"ec1a0b44-7e92-40a5-811c-4514025c688b","priority":"e935fdd5-e770-4fd1-bf76-27c832b5cb83","contactId":"5198411d-e7d8-4c11-a018-95ee78f7ebcf"}'
customer_profiles_domain_name = "connect-demo-banking-sandbox"
```

---

### 🔧 Ejecutar terraform plan con credenciales del profile sandbox

**Por qué:** Terraform no tiene credenciales configuradas por defecto en el entorno local. El provider AWS en `versions.tf` no especifica un profile, por lo que hay que pasarlo como variable de entorno antes de correr cualquier comando de Terraform. Sin esto Terraform intenta buscar credenciales en EC2 IMDS y falla.

**Contexto:** Se usa `AWS_PROFILE=sandbox` para apuntar al profile configurado en `~/.aws/config` que tiene acceso al account `063103265536`. El `-out` guarda el plan compilado para hacer el apply sin que nada cambie entre medias. El `tee` muestra la salida en pantalla y la guarda en archivo para revisión.

```bash
# Desde infra/environments/sandbox
export AWS_PROFILE=sandbox
terraform plan -out=tfplan-v3.out 2>&1 | tee /tmp/tfplan-v3.txt
```

**Para el apply (una vez revisado el plan):**
```bash
export AWS_PROFILE=sandbox
terraform apply tfplan-v3.out
```

**Nota:** `AWS_PROFILE` solo aplica a la sesión de terminal activa. Si abres una nueva terminal hay que exportarlo de nuevo, o agregarlo al provider en `versions.tf` con `profile = "sandbox"`.

---

### 🔧 Actualizar el flujo V3 de Connect manualmente (sin terraform apply)

**Por qué:** Cuando se modifica el archivo `infra/modules/connect/flows/banking-v3.json` es más rápido aplicar el cambio directo con la CLI que regenerar el plan de Terraform. Útil para iteraciones rápidas de prueba del flujo.

**Contexto:** El archivo JSON usa variables de Terraform (`${lex_bot_alias_arn}`, etc.) que hay que sustituir antes de enviarlo a la API. El script Python hace esa sustitución con los valores reales del sandbox.

```bash
# Desde la raíz del proyecto
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
  .replace('\${fraud_queue_id}', '482b6530-19b5-42cd-8b6f-46b4fab07220')
with open('/tmp/banking-v3-expanded.json', 'w') as f: f.write(content)
print('JSON generado OK')
" && aws connect update-contact-flow-content \
  --instance-id 6198ee3d-76f0-4a24-8171-e50d802c8871 \
  --contact-flow-id b19c9caf-c23d-450a-8d14-92f374121442 \
  --content "$(cat /tmp/banking-v3-expanded.json)" \
  --region us-east-1 \
  --profile sandbox \
  --cli-error-format json 2>&1 && echo "✅ Flujo actualizado correctamente"
```

---

### 🔧 Redesplegar una Lambda específica sin terraform apply completo

**Por qué:** Cuando solo se modifica el código Python de una Lambda (sin cambios de infraestructura), es más rápido usar `terraform plan -target` que regenerar el plan completo.

**Contexto:** El `-target` limita el plan y apply a un solo recurso. Útil para iterar rápido en el código de las Lambdas sin arriesgar cambios en otros recursos.

```bash
cd /Users/daryelispinate/Desktop/proyectosIVCISA/connect-demo-infra/infra/environments/sandbox
export AWS_PROFILE=sandbox

# Redesplegar get-transactions
terraform plan -target='module.lambda.aws_lambda_function.tool["get-transactions"]' -out=tfplan-lambda.out
terraform apply tfplan-lambda.out

# Redesplegar block-card
terraform plan -target='module.lambda.aws_lambda_function.tool["block-card"]' -out=tfplan-lambda.out
terraform apply tfplan-lambda.out

# Redesplegar create-fraud-case
terraform plan -target='module.lambda.aws_lambda_function.tool["create-fraud-case"]' -out=tfplan-lambda.out
terraform apply tfplan-lambda.out
```

**Nota:** Si se modificaron variables de entorno de la Lambda, también hay que incluir el recurso de `aws_lambda_function` en el target (ya está incluido arriba).

---

## 09/10/2026 — Prueba completa: caso de fraude en workspace del agente

---

### 🔍 Verificar configuración de la Lambda create-fraud-case

**Por qué:** Confirmar que la Lambda existe, tiene las variables de entorno correctas y el rol IAM asociado.

```bash
aws lambda get-function-configuration \
  --function-name connect-demo-banking-sandbox-create-fraud-case \
  --region us-east-1 --profile sandbox \
  --query '{FunctionArn:FunctionArn,Runtime:Runtime,Handler:Handler,Role:Role,Timeout:Timeout,LastModified:LastModified,Environment:Environment.Variables}'
```

**Resultado:** ✅ Lambda existe. Runtime `python3.11`, handler `handler.lambda_handler`, rol `connect-demo-banking-sandbox-create-fraud-case-role`, todas las variables de entorno presentes (`CASES_DOMAIN_ID`, `CASES_TEMPLATE_ID`, `CASES_FIELD_IDS`, `CUSTOMER_PROFILES_DOMAIN`, `DYNAMODB_TABLE_NAME`).

---

### 🔍 Verificar plantilla Cases

```bash
aws connectcases list-templates \
  --domain-id 0c507c5e-02b9-4f30-82f9-d9cc20fac1d8 \
  --region us-east-1 --profile sandbox
```

**Resultado:** ✅ Plantilla `Reporte de fraude bancario` (`42cdb67b-8256-4656-80e6-637cb5e8fe34`) en estado `Active`.

---

### 🔍 Verificar permisos del security profile del agente

```bash
aws connect list-security-profile-permissions \
  --instance-id 6198ee3d-76f0-4a24-8171-e50d802c8871 \
  --security-profile-id 7cfc0a57-1341-4b9e-9a39-21890df4a392 \
  --region us-east-1 --profile sandbox
```

**Resultado:** ✅ Permisos confirmados en `connect-demo-banking-sandbox-agent-profile`:
- `Cases.Create`, `Cases.Edit`, `Cases.View`
- `CustomerProfiles.View`
- `BasicAgentAccess`, `OutboundCallAccess`

El usuario `demo-agent` (`046061ae-b5ef-4519-9772-fc6010be70c8`) tiene asignado este perfil.

---

### 🐛 Bug #1 — Campo `title` faltaba en `fields[]` de CreateCase

**Descubierto con:**
```bash
aws connectcases create-case \
  --domain-id 0c507c5e-02b9-4f30-82f9-d9cc20fac1d8 \
  --template-id 42cdb67b-8256-4656-80e6-637cb5e8fe34 \
  --fields '[
    {"id":"a7f0ea33-f713-4889-a76e-04e40ea97ef0","value":{"stringValue":"CUS-2001"}},
    {"id":"e8281ec5-970f-4d5d-863c-56b635256cba","value":{"stringValue":"TXN-9002"}},
    {"id":"1b37058d-0826-4145-beb3-bf1392ead7bf","value":{"stringValue":"****4455"}},
    {"id":"55d8e18f-37f6-4866-a0a5-d1d2a00403e9","value":{"stringValue":"BLOCKED"}}
  ]' \
  --client-token "CLI-TEST-$(date +%s)" \
  --region us-east-1 --profile sandbox
```

**Error:** `ValidationException: Field(s) title are required`

**Causa:** `build_case_fields()` no incluía el campo de sistema `title` (fieldId literal `"title"`). El handler construía `case_title` como variable local pero nunca lo agregaba al array `fields`.

**Fix aplicado en:** `src/tools/create_fraud_case/handler.py`
- `build_case_fields()` ahora recibe `case_title` como tercer parámetro y lo inserta primero como `{"id": "title", "value": {"stringValue": ...}}`.
- El bloque `except Exception` en `create_case` ahora loggea `str(exc)` para visibilidad futura.
- Se eliminó el parámetro `performedBy` con valor vacío que no aportaba nada.

---

### 🐛 Bug #2 — Política IAM `cases:CreateCase` sin ARN base del dominio

**Descubierto con (primer intento de invoke Lambda post-fix del bug #1):**
```bash
aws logs filter-log-events \
  --log-group-name "/aws/lambda/connect-demo-banking-sandbox-create-fraud-case" \
  --start-time $(($(date +%s) * 1000 - 300000)) \
  --filter-pattern "" \
  --limit 30 \
  --region us-east-1 --profile sandbox
```

**Error en el log:** `AccessDeniedException: not authorized to perform: cases:CreateCase on resource: arn:aws:cases:us-east-1:063103265536:domain/0c507c5e-02b9-4f30-82f9-d9cc20fac1d8`

**Causa:** La política `connect-demo-banking-sandbox-create-fraud-case-cases-policy` solo tenía `Resource: "...domain/<id>/*"`. La API de `CreateCase` evalúa el permiso contra el ARN base del dominio (sin wildcard), que no estaba cubierto.

**Fix aplicado en:** `infra/modules/iam/main.tf`
```hcl
# Antes
Resource = "arn:aws:cases:...domain/${var.cases_domain_id}/*"

# Después
Resource = [
  "arn:aws:cases:...domain/${var.cases_domain_id}",   # ARN base (requerido por CreateCase)
  "arn:aws:cases:...domain/${var.cases_domain_id}/*"  # recursos hijos
]
```

**Desplegado con:**
```bash
cd infra/environments/sandbox && export AWS_PROFILE=sandbox
terraform plan -target='module.iam.aws_iam_policy.create_fraud_case_cases' -out=tfplan-iam-cases.out
terraform apply tfplan-iam-cases.out
```

---

### 🔧 Redesplegar Lambda create-fraud-case con el fix del bug #1

```bash
cd infra/environments/sandbox && export AWS_PROFILE=sandbox
rm -f ../../modules/lambda/.build/create-fraud-case.zip
terraform plan -target='module.lambda.aws_lambda_function.tool["create-fraud-case"]' -out=tfplan-createcase.out
terraform apply tfplan-createcase.out
```

**Resultado:** ✅ `Apply complete! Resources: 0 added, 1 changed, 0 destroyed.`

---

### 🔧 Prueba unitaria completa — invoke Lambda create-fraud-case

```bash
OP_ID="FRAUD-CUS-2001-TXN-9002-$(date +%s)"

cat > /tmp/create-case-test-v3.json << PAYLOAD
{
  "Details": {
    "ContactData": {
      "ContactId": "test-contact-manual-003",
      "InstanceARN": "arn:aws:connect:us-east-1:063103265536:instance/6198ee3d-76f0-4a24-8171-e50d802c8871",
      "Channel": "VOICE",
      "Attributes": {}
    },
    "Parameters": {
      "customerId": "CUS-2001",
      "transactionId": "TXN-9002",
      "cardReference": "****4455",
      "blockResult": "BLOCKED",
      "consent": "true",
      "blockedAt": "2026-10-09T20:30:00Z",
      "operationId": "${OP_ID}"
    }
  }
}
PAYLOAD

aws lambda invoke \
  --function-name connect-demo-banking-sandbox-create-fraud-case \
  --cli-binary-format raw-in-base64-out \
  --payload file:///tmp/create-case-test-v3.json \
  --region us-east-1 --profile sandbox \
  /tmp/create-case-response-v3.json

cat /tmp/create-case-response-v3.json
```

**Resultado:** ✅
```json
{
  "success": "true",
  "caseId": "dc8f656b-721d-3e25-8683-bc62ddbee01a",
  "caseArn": "arn:aws:cases:us-east-1:063103265536:domain/0c507c5e-02b9-4f30-82f9-d9cc20fac1d8/case/dc8f656b-721d-3e25-8683-bc62ddbee01a",
  "caseCreated": "true",
  "contactLinked": "false",
  "errorCode": ""
}
```

> `contactLinked: false` es esperado en prueba unitaria — el `ContactId` es inventado. En el flujo real de Connect el ContactId es real y el link funciona.

---

### 🔍 Confirmar que el caso aparece en Connect Cases

```bash
aws connectcases search-cases \
  --domain-id 0c507c5e-02b9-4f30-82f9-d9cc20fac1d8 \
  --fields '[
    {"id":"title"},
    {"id":"status"},
    {"id":"a7f0ea33-f713-4889-a76e-04e40ea97ef0"},
    {"id":"55d8e18f-37f6-4866-a0a5-d1d2a00403e9"},
    {"id":"e8281ec5-970f-4d5d-863c-56b635256cba"}
  ]' \
  --region us-east-1 --profile sandbox
```

**Resultado:** ✅ Casos visibles en el dominio:

| caseId | title | status | blockResult |
|--------|-------|--------|-------------|
| `dc8f656b-...` | Fraude CUS-2001 - TXN-9002 | open | BLOCKED |
| `8b2ae72b-...` | Fraude CUS-2001 - TXN-9002 (CLI-TEST) | open | BLOCKED |

El caso creado por Lambda está disponible para que el agente lo vea en su workspace de Connect.

---

### 🔧 Crear perfiles en Customer Profiles para CUS-3001 a CUS-3005

**Por qué:** La Lambda `create_fraud_case` hace `SearchProfiles` por `_account` para resolver el ProfileId del cliente. Sin perfil no puede vincular el caso al cliente en Connect.

```bash
for ID in 3001 3002 3003 3004 3005; do
  aws customer-profiles search-profiles \
    --domain-name connect-demo-banking-sandbox \
    --key-name _account --values "CUS-${ID}" \
    --region us-east-1 --profile sandbox \
    --query 'Items[0].ProfileId' --output text
done
# Todos devolvían None → se procedió a crearlos

aws customer-profiles create-profile --domain-name connect-demo-banking-sandbox \
  --account-number "CUS-3001" --first-name "Ana" --last-name "Torres" \
  --region us-east-1 --profile sandbox
# Idem para CUS-3002..3005 con sus nombres correspondientes
```

**Resultado:** ✅ 5 perfiles creados y verificados con SearchProfiles:

| Customer ID | ProfileId | Nombre |
|---|---|---|
| CUS-3001 | `5987135f636b468da873d39101865795` | Ana Torres |
| CUS-3002 | `2ccf35479ecb44049aa8511729c75944` | Carlos Mendoza |
| CUS-3003 | `0a07fc1448cd463cbb535c45444b8662` | María Rodríguez |
| CUS-3004 | `0a83546194fa49a7bceba1450cdbeafb` | Jorge Vázquez |
| CUS-3005 | `cc8c94d6ecc540b2856559fec144eca3` | Laura Castillo |
