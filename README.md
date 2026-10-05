# connect-demo-infra

Infraestructura como código para la demo de Amazon Connect — Retail y Banca.

Gestiona todos los recursos AWS necesarios utilizando Terraform como herramienta principal, con CloudFormation únicamente cuando Terraform no cubre adecuadamente algún recurso.

---

## Casos de uso implementados

### Retail
- Consulta del estado de un pedido.
- Detección de pedido retrasado.
- Cambio de dirección o reprogramación de entrega.
- Escalación a agente humano con contexto completo.

### Banca
- Consulta de movimientos recientes.
- Identificación de transacción sospechosa.
- Bloqueo de tarjeta ante fraude, robo o pérdida.
- Escalación a agente humano con contexto completo.

---

## Estructura del repositorio

```
connect-demo-infra/
├── infra/
│   ├── environments/
│   │   └── sandbox/          # Composición de módulos para sandbox
│   ├── modules/
│   │   ├── connect/          # Amazon Connect
│   │   ├── agentcore/        # Bedrock AgentCore Runtime + Gateway
│   │   ├── lambda/           # Funciones Lambda (tools)
│   │   ├── dynamodb/         # Tabla ConnectDemoData
│   │   ├── iam/              # Roles y políticas IAM
│   │   └── observability/    # CloudWatch Logs y métricas
│   └── bootstrap/            # Backend S3 + DynamoDB lock para estado Terraform
├── src/
│   ├── tools/                # Código fuente de las 4 Lambdas
│   │   ├── get_order/
│   │   ├── change_delivery_address/
│   │   ├── get_transactions/
│   │   └── block_card/
│   └── agent/                # Configuración del agente AgentCore
├── config/
│   └── sandbox.yaml          # Parámetros por ambiente
├── scripts/
│   ├── deploy.sh
│   ├── destroy.sh
│   └── seed_data.sh
├── tests/
│   ├── unit/
│   └── e2e/
├── docs/
│   ├── architecture.md
│   ├── runbook-deployment.md
│   ├── runbook-troubleshooting.md
│   └── runbook-cleanup.md
└── cloudformation/           # Solo para recursos sin soporte completo en Terraform
```

---

## Prerrequisitos

- AWS CLI >= 2.x configurado con credenciales válidas
- Terraform >= 1.9.5 (usar `tfenv` para gestionar versiones)
- Python >= 3.11 (para el código Lambda y scripts)
- Permisos AWS sobre: IAM, Lambda, DynamoDB, Connect, Bedrock, CloudWatch, S3

```bash
# Verificar prerrequisitos
aws --version
terraform version
python3 --version
aws sts get-caller-identity
```

---

## Despliegue rápido

### 1. Bootstrap del backend Terraform (solo la primera vez)

```bash
cd infra/bootstrap
terraform init
terraform apply
```

### 2. Desplegar el ambiente sandbox

```bash
cd infra/environments/sandbox
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### 3. Cargar datos ficticios en DynamoDB

```bash
bash scripts/seed_data.sh
```

### 4. Script completo de despliegue

```bash
bash scripts/deploy.sh sandbox
```

---

## Destruir el entorno

```bash
bash scripts/destroy.sh sandbox
```

> Ver `docs/runbook-cleanup.md` para recursos que pueden requerir eliminación manual.

---

## Configuración

Editar `config/sandbox.yaml` para ajustar región, alias de instancia Connect, modelo Bedrock, etc.

Los valores sensibles se almacenan en AWS SSM Parameter Store o Secrets Manager, nunca en archivos versionados.

---

## Módulos

| Módulo | Responsabilidad | Compartido |
|---|---|---|
| `iam` | Roles y políticas con mínimo privilegio | Sí |
| `dynamodb` | Tabla `ConnectDemoData` single-table | Sí |
| `lambda` | Las 4 tools: get_order, change_delivery_address, get_transactions, block_card | Sí |
| `observability` | CloudWatch Logs, métricas, correlation IDs | Sí |
| `agentcore` | Bedrock AgentCore Runtime + Gateway + tools | Sí |
| `connect` | Instancia Connect, queues, routing, flows | Sí (instancia compartida) |

---

## Documentación

- [Arquitectura](docs/architecture.md)
- [Runbook de despliegue](docs/runbook-deployment.md)
- [Runbook de troubleshooting](docs/runbook-troubleshooting.md)
- [Runbook de cleanup](docs/runbook-cleanup.md)
