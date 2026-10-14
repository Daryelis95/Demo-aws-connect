# Scripts para Agregar Intents a Lex

Este directorio contiene herramientas para expandir el bot `BankingFraudBot` con intents adicionales para manejar múltiples variaciones de "reportar fraude".

---

## 📋 Archivos

### 1. `add-fraud-intents.sh`
**Script Bash para validación (sin cambios)**

**Uso**:
```bash
chmod +x scripts/add-fraud-intents.sh
./scripts/add-fraud-intents.sh \
  --region us-east-1 \
  --profile sandbox
```

**Qué hace**:
- ✅ Valida que el bot `BankingFraudBot` existe
- ✅ Lista los intents actuales
- ✅ Muestra los utterances recomendados para cada intent nuevo
- ❌ NO hace cambios (solo consulta)

**Salida esperada**:
```
========================================
Bot Lex: Agregar intents para fraude
==========================================
Región: us-east-1
Perfil: sandbox
Dry Run: false

📋 Verificando bot...
✅ Bot encontrado: BankingFraudBot (NXHHCKVHHM)

📦 Versión del bot: DRAFT

📝 Intents actuales:
+----+--+
| ... |
```

**Requisitos**:
- AWS CLI v2 instalado
- Credenciales configuradas (perfil `sandbox`)
- Permiso `lex:ListIntents` en IAM

---

### 2. `create_lex_intents.py`
**Script Python para crear/actualizar intents**

**Uso**:
```bash
# Prerequisito: instalar boto3
pip install boto3>=1.26.0

# Ejecutar
python3 scripts/create_lex_intents.py \
  --region us-east-1 \
  --profile sandbox \
  --bot-id NXHHCKVHHM \
  --bot-version DRAFT \
  --locale-id es_419
```

**Qué hace**:
- ✅ Lista intents existentes
- ✅ Crea intents nuevos (ReportFraud, ReportUnauthorized, BlockCard, etc.)
- ✅ Actualiza utterances si el intent ya existe (en versión DRAFT)
- ✅ Genera un resumen con contadores

**Salida esperada**:
```
INFO: ==================================================
INFO: Gestor de Intents - Lex V2
INFO: ==================================================
INFO: Bot ID: NXHHCKVHHM
INFO: Versión: DRAFT
INFO: Locale: es_419
INFO:
INFO: Intents existentes (1):
INFO:   • ReportFraud (ABCD1234)
INFO:
INFO: Procesando intent: ReportFraud
INFO:   ✏️ Actualizando utterances para: ReportFraud
INFO:   ✅ Intent actualizado: ReportFraud
...
INFO: ==================================================
INFO: Resumen:
INFO:   ✅ Creados: 4
INFO:   ✏️ Actualizados: 1
INFO:   ⏭️ Saltados: 0
INFO: ==================================================
INFO:
INFO: ⚠️  IMPORTANTE: Debes compilar el bot para aplicar cambios
INFO:    1. Accede a: https://console.aws.amazon.com/lexv2/
INFO:    2. Selecciona BankingFraudBot
INFO:    3. Haz clic en 'Build'
...
```

**Requisitos**:
- Python 3.7+
- boto3 >= 1.26.0: `pip install boto3`
- Credenciales AWS configuradas
- Permisos `lex:CreateIntent`, `lex:UpdateIntent`, `lex:ListIntents`

---

## 🚀 Guía Paso a Paso

### Opción 1: Crear Intents Manualmente (Consola)

Si prefieres no ejecutar scripts, puedes crear los intents directamente desde la consola:

1. Accede a [AWS Lex Console](https://console.aws.amazon.com/lexv2/)
2. Selecciona **BankingFraudBot** (o busca por ID: `NXHHCKVHHM`)
3. Ve a la pestaña **Intents** (dentro del locale `es-419`)
4. Crea cada intent:

#### Intent: `ReportFraud`
- **Description**: Reportar fraude
- **Sample utterances**:
  - quiero reportar un fraude
  - hay fraude en mi cuenta
  - sospechos de fraude
  - reportar actividad fraudulenta
  - tengo un fraude
  - fraude
  - reportar fraude

#### Intent: `ReportUnauthorized`
- **Description**: Movimiento no autorizado
- **Sample utterances**:
  - hay un movimiento no autorizado
  - no reconozco este cargo
  - no autorizo este movimiento
  - movimiento no reconocido
  - cargo no autorizado
  - no autorizado
  - cargo que no hice

#### Intent: `BlockCard`
- **Description**: Bloqueo de tarjeta
- **Sample utterances**:
  - bloquea mi tarjeta
  - quiero bloquear mi tarjeta
  - bloquear mi cuenta
  - deshabilitar mi tarjeta
  - desactiva mi tarjeta
  - quiero que bloquees mi tarjeta
  - bloquea mi tarjeta por seguridad

#### Intent: `SuspiciousTransaction`
- **Description**: Transacción sospechosa
- **Sample utterances**:
  - hay una transacción sospechosa
  - movimiento sospechoso
  - cargo sospechoso
  - transacción extraña
  - operación sospechosa
  - veo un cargo que no reconozco
  - hay cargos raros

#### Intent: `ReportFraudVariant`
- **Description**: Variaciones de reportar fraude
- **Sample utterances**:
  - reportar un cargo fraudulento
  - tengo fraude
  - actividad fraudulenta en mi cuenta
  - fraude en mi tarjeta
  - detecté fraude
  - creo que me han defraudado
  - hay fraude aquí

5. Una vez creados los intents, haz clic en **Build** (botón en la parte superior)
6. Espera a que termine la compilación (2-3 minutos)

---

### Opción 2: Crear Intents con Script Python (Recomendado)

1. **Verificar intents actuales** (sin cambios):
   ```bash
   ./scripts/add-fraud-intents.sh --profile sandbox
   ```

2. **Instalar dependencias**:
   ```bash
   pip install boto3>=1.26.0
   ```

3. **Ejecutar el script de creación**:
   ```bash
   python3 scripts/create_lex_intents.py \
     --region us-east-1 \
     --profile sandbox
   ```

4. **Compilar el bot** (desde la consola):
   - Accede a [AWS Lex Console](https://console.aws.amazon.com/lexv2/)
   - Selecciona **BankingFraudBot**
   - Haz clic en **Build**
   - Espera a que termine

5. **Actualizar el alias** (opcional):
   - Ve a **Aliases**
   - Edita **SandboxBanking**
   - Selecciona la versión compilada más reciente
   - Guarda

---

## ✅ Validación

### Test Manual en Chat

Una vez que el bot esté compilado:

1. Abre el flujo V3 en Amazon Connect (chat o voz)
2. Prueba las siguientes entradas:
   - "bloquea mi tarjeta" → debe reconocer `BlockCard`
   - "no reconozco este cargo" → debe reconocer `ReportUnauthorized`
   - "hay una transacción sospechosa" → debe reconocer `SuspiciousTransaction`
   - "reportar un cargo fraudulento" → debe reconocer `ReportFraudVariant`

**Esperado**: Todas las entradas conducen a "¿Cuál es tu número de cliente?"

### Test Automatizado (Futuro)

```bash
# Script para probar intents (crear después)
python3 scripts/test_lex_intents.py \
  --bot-id NXHHCKVHHM \
  --alias-id ZSII5DJKMX \
  --profile sandbox
```

---

## 🔧 Troubleshooting

### Error: `ResourceNotFoundException`
```
botocore.exceptions.ClientError: An error occurred (ResourceNotFoundException)
```
**Solución**: Verifica que el `bot-id` y `bot-version` son correctos. Usa:
```bash
aws lex list-bots --region us-east-1 --profile sandbox
```

### Error: `AccessDeniedException`
```
botocore.exceptions.ClientError: An error occurred (AccessDeniedException)
```
**Solución**: Las credenciales de AWS no tienen permisos. Verifica que:
1. El perfil `sandbox` está configurado correctamente
2. El usuario/rol tiene `lex:*` permissions
3. Ejecuta: `aws sts get-caller-identity --profile sandbox`

### Error: `ModuleNotFoundError: No module named 'boto3'`
**Solución**: Instala boto3:
```bash
pip install boto3>=1.26.0
```

---

## 📚 Referencias

- **Especificación de intents**: Ver `.kiro/lex-intents-specification.md`
- **Contexto del proyecto**: Ver `.kiro/contexto-v3.md`
- **AWS Lex Docs**: https://docs.aws.amazon.com/lexv2/latest/developerguide/
- **boto3 Lex API**: https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/lexv2-models.html

---

## 🆘 Soporte Futuro en Terraform

Actualmente, Terraform **no soporta** recursos `aws_lexv2_bot_intent` (issue [#33934](https://github.com/hashicorp/terraform-provider-aws/issues/33934)).

Cuando esté disponible, los intents se gestionarán directamente desde `infra/modules/lex/`.

Ver documento: `infra/modules/lex/FUTURE_SUPPORT.md`

---

**Última actualización**: 2026-10-11  
**Mantenedor**: Team Infra  
**Estado**: 🟡 Scripts listos para usar
