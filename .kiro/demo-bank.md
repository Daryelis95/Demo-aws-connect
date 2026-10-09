# Infraestructura como Código — Amazon Connect Demo

Guía paso a paso para crear y estructurar el proyecto Terraform separado que implementa la demo de Amazon Connect (Retail + Banca).

---

## 1. Crear el repositorio de infraestructura

El código de infraestructura vive en un repositorio independiente del frontend.

```bash
# Crear el directorio fuera del repo del frontend
mkdir connect-demo-infra
cd connect-demo-infra
git init
```

> Este proyecto es completamente independiente del frontend. No lo crees dentro de `frontend-alpha-ib/frontend`.

---

## 2. Estructura del repositorio

```
connect-demo-infra/
├── infra/
│   ├── environments/
│   │   └── sandbox/
│   │       ├── main.tf          # Composición de módulos para sandbox
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       └── terraform.tfvars # Variables de sandbox (NO versionar secretos)
│   ├── modules/
│   │   ├── connect/             # Amazon Connect: instancia, flows, queues, routing
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── agentcore/           # Bedrock AgentCore Runtime + Gateway
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── lambda/              # Funciones Lambda (tools: get_order, block_card, etc.)
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── dynamodb/            # Tabla ConnectDemoData
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── iam/                 # Roles y políticas IAM
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   └── observability/       # CloudWatch Logs, métricas, correlation IDs
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── outputs.tf
│   └── bootstrap/               # Terraform backend en S3 + DynamoDB lock
│       ├── main.tf
│       └── variables.tf
├── src/
│   ├── tools/                   # Código fuente de las Lambdas (Python o Node.js)
│   │   ├── get_order/
│   │   ├── change_delivery_address/
│   │   ├── get_transactions/
│   │   └── block_card/
│   └── agent/                   # Configuración del agente AgentCore / Strands
├── config/
│   └── sandbox.yaml             # Parámetros de configuración por ambiente
├── scripts/
│   ├── deploy.sh                # Script de despliegue completo
│   ├── destroy.sh               # Script de limpieza
│   └── seed_data.sh             # Carga de datos ficticios en DynamoDB
├── tests/
│   ├── unit/                    # Tests unitarios de cada Lambda
│   └── e2e/                     # Tests end-to-end Connect → Agent → DynamoDB
├── docs/
│   ├── architecture.md
│   ├── runbook-deployment.md
│   ├── runbook-troubleshooting.md
│   └── runbook-cleanup.md
├── cloudformation/              # Plantillas CFN solo para recursos sin soporte Terraform
│   └── connect-instance.yaml    # Si Amazon Connect requiere CFN
├── .gitignore
├── .terraform-version           # Versión exacta de Terraform
└── README.md
```

---

## 3. Prerrequisitos

Antes de ejecutar cualquier comando Terraform, verificar que tienes:

- [ ] AWS CLI instalado y configurado (`aws configure`)
- [ ] Credenciales con permisos sobre: IAM, Lambda, DynamoDB, Connect, Bedrock, CloudWatch, S3
- [ ] Terraform >= 1.6 instalado (usar `tfenv` para gestionar versiones)
- [ ] Python 3.11+ (para el código de las Lambdas)
- [ ] Acceso a la cuenta sandbox de AWS validado
- [ ] Región objetivo definida (por ejemplo: `us-east-1`)
- [ ] Amazon Bedrock habilitado en la región con acceso al modelo seleccionado

```bash
# Verificar versiones
aws --version
terraform version
python3 --version

# Verificar identidad de AWS
aws sts get-caller-identity --profile sandbox
```

---

## 4. Paso a paso de implementación por fases

### Fase 1 — Arquitectura y validación (manual / diseño)

Antes de escribir código:

1. Revisar qué recursos de Amazon Connect tienen soporte nativo en el provider `hashicorp/aws`.
2. Identificar si `aws_connect_instance` y `aws_connect_contact_flow` están disponibles en la versión del provider que se usará.
3. Confirmar si Bedrock AgentCore tiene recursos Terraform o requiere CloudFormation / CLI.
4. Definir la región donde se habilitará Amazon Connect (no todas las regiones soportan todos los canales).
5. Validar que el sandbox tenga límites de servicio suficientes.

> **Resultado esperado:** diagrama Mermaid aprobado + árbol del repositorio confirmado.

---

### Fase 2 — Bootstrap del backend de Terraform

El estado de Terraform debe almacenarse en S3 con locking en DynamoDB.

```bash
cd infra/bootstrap
terraform init
terraform apply
```

Esto crea:
- Bucket S3 para el state file (versionado, cifrado).
- Tabla DynamoDB para el lock del estado.

Luego configurar el backend en `infra/environments/sandbox/main.tf`:

```hcl
terraform {
  backend "s3" {
    bucket         = "connect-demo-tfstate-sandbox"
    key            = "sandbox/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "connect-demo-tfstate-lock"
    encrypt        = true
  }
}
```

---

### Fase 3 — Fundación IaC

Implementar los módulos base en este orden:

1. **IAM** — Roles de ejecución Lambda, permisos DynamoDB, permisos AgentCore, integración Connect.
2. **DynamoDB** — Tabla `ConnectDemoData` con modelo single-table.
3. **Lambda** — Empaquetar y desplegar las cuatro tools (`get_order`, `change_delivery_address`, `get_transactions`, `block_card`).
4. **Observabilidad** — Log groups en CloudWatch, structured JSON logging, correlation IDs.

```bash
cd infra/environments/sandbox
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Validar:
```bash
# Verificar que la tabla DynamoDB existe
aws dynamodb describe-table --table-name ConnectDemoData

# Verificar que las Lambdas existen
aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `connect-demo`)]'
```

Cargar datos ficticios:
```bash
bash scripts/seed_data.sh
```

---

### Fase 4 — AgentCore

1. Configurar Bedrock AgentCore Runtime.
2. Configurar AgentCore Gateway con las cuatro tools.
3. Asignar permisos IAM para que AgentCore pueda invocar las Lambdas.
4. Probar el agente de forma independiente antes de conectarlo a Amazon Connect.

> **Nota:** si `aws_bedrock_agent` o recursos de AgentCore no tienen soporte completo en Terraform, se usará CloudFormation (`cloudformation/agentcore.yaml`) invocado desde Terraform con `aws_cloudformation_stack`.

Prueba independiente:
```bash
# Invocar el agente directamente (sin Connect)
python3 tests/unit/test_agent_retail.py
python3 tests/unit/test_agent_banking.py
```

---

### Fase 5 — Amazon Connect

1. Crear la instancia de Amazon Connect (compartida entre Retail y Banca).
2. Configurar:
   - Security Profile
   - Routing Profile
   - Queue (Retail + Banca)
   - Contact Flows
   - Usuario agente
3. Integrar Lambda / AgentCore con los Contact Flows.
4. Habilitar chat.

> **Advertencia:** la creación de instancias Amazon Connect puede no estar completamente soportada por Terraform. Revisar si se requiere paso manual desde consola o CloudFormation.

Pasos manuales posibles (documentar si aplican):
- Crear la instancia desde AWS Console si `aws_connect_instance` no está disponible.
- Reclamar un número telefónico (limitado en sandbox).
- Publicar Contact Flows.

```bash
# Verificar instancia Connect
aws connect list-instances
```

---

### Fase 6 — End-to-end y calidad

1. Ejecutar pruebas end-to-end:

```bash
# Retail: consulta de pedido
python3 tests/e2e/test_retail_order.py

# Banca: bloqueo de tarjeta
python3 tests/e2e/test_banking_block_card.py

# Handoff a agente humano
python3 tests/e2e/test_handoff.py
```

2. Verificar que el contexto llega al agente humano correctamente.
3. Revisar los logs en CloudWatch:

```bash
aws logs tail /aws/lambda/connect-demo-get-order --follow
aws logs tail /aws/lambda/connect-demo-block-card --follow
```

---

## 5. Variables de configuración principales

Definir en `config/sandbox.yaml` o en `terraform.tfvars`:

```yaml
aws_region: "us-east-1"
environment: "sandbox"
project_name: "connect-demo"
connect_instance_alias: "connect-demo-sandbox"
language: "es-US"
bedrock_model_id: "anthropic.claude-3-sonnet-20240229-v1:0"
retail_queue_name: "RetailQueue"
banking_queue_name: "BankingQueue"
```

> **Nunca versionar** `terraform.tfvars` si contiene secretos. Usar `.gitignore` para excluirlo y AWS Secrets Manager o SSM Parameter Store para valores sensibles.

---

## 6. Secretos y seguridad

- No almacenar tokens, claves ni passwords en el código ni en tfvars versionados.
- Usar SSM Parameter Store para configuraciones sensibles no secretas.
- Usar Secrets Manager para credenciales de terceros (si aplica en producción).
- Los roles Lambda deben tener políticas con mínimo privilegio.
- Evitar `Action: "*"` o `Resource: "*"` en políticas IAM.

---

## 7. Destruir el entorno

```bash
cd infra/environments/sandbox
terraform destroy
```

Recursos que pueden no eliminarse automáticamente con `terraform destroy`:

| Recurso | Motivo |
|---|---|
| Instancia Amazon Connect | Puede requerir eliminación manual desde consola |
| Números telefónicos Connect | Deben liberarse antes de destruir la instancia |
| CloudWatch Log Groups | Terraform no siempre los elimina si tienen retención |
| S3 bucket del state | Debe eliminarse manualmente (tiene versionado) |
| AgentCore resources | Depende del soporte Terraform disponible |

Runbook completo de limpieza: `docs/runbook-cleanup.md`

---

## 8. Costos a revisar antes de dejar el sandbox activo

| Servicio | Tipo de costo |
|---|---|
| Amazon Connect | Por minuto de uso (voz) + por contacto (chat) |
| Bedrock AgentCore | Por token procesado |
| Lambda | Por invocación (capa gratuita generosa) |
| DynamoDB | On-demand, por lectura/escritura |
| CloudWatch Logs | Por GB ingestado y almacenado |
| S3 (state) | Mínimo en sandbox |
| EventBridge | Por evento (si se habilita proactividad) |

> Apagar o destruir el entorno sandbox cuando no esté en uso activo para evitar costos innecesarios.

---

## 9. Orden recomendado de implementación

```
1. Bootstrap (S3 state + DynamoDB lock)
       ↓
2. IAM (roles y políticas base)
       ↓
3. DynamoDB + seed data
       ↓
4. Lambdas (tools)
       ↓
5. Observabilidad (CloudWatch)
       ↓
6. AgentCore (Runtime + Gateway + tools)
       ↓
7. Amazon Connect (instancia + routing + flows)
       ↓
8. Integración end-to-end
       ↓
9. Pruebas + documentación
```

---

## 10. Referencias

- [Terraform AWS Provider — Amazon Connect](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/connect_instance)
- [Amazon Bedrock AgentCore](https://docs.aws.amazon.com/bedrock/latest/userguide/agents.html)
- [Amazon Connect Admin Guide](https://docs.aws.amazon.com/connect/latest/adminguide/)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/)
