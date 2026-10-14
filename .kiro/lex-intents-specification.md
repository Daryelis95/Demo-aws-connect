# Especificación: Nuevos Intents en Lex para Reportes de Fraude

## Objetivo
Expandir el bot `BankingFraudBot` (ID: `NXHHCKVHHM`) para manejar múltiples variaciones naturales de "quiero reportar fraude" en español latinoamericano (`es-419`).

**Estado**: 🔄 En implementación  
**Prioridad**: Media (mejora de UX, no bloqueante)  
**Región**: `us-east-1`  
**Alias**: `SandboxBanking` (ZSII5DJKMX)

---

## Intents a Crear/Actualizar

### 1. **ReportFraud** (Existente - Validar)
**Propósito**: Intent principal para reportar fraude general.

**Utterances Recomendadas**:
- "quiero reportar un fraude"
- "hay fraude en mi cuenta"
- "sospechos de fraude"
- "reportar actividad fraudulenta"
- "tengo un fraude"
- "fraude"
- "reportar fraude"

**Slot**: None (evento simple)  
**Fulfillment**: Retorna intent `ReportFraud` al flujo Connect  
**Prioridad de la acción**: Ir a "Solicitar ID Cliente"

---

### 2. **ReportUnauthorized** (Nuevo)
**Propósito**: Movimientos no autorizados o no reconocidos.

**Utterances**:
- "hay un movimiento no autorizado"
- "no reconozco este cargo"
- "no autorizo este movimiento"
- "movimiento no reconocido"
- "cargo no autorizado"
- "no autorizado"
- "cargo que no hice"
- "esto no fui yo"

**Slot**: Opcional - `TransactionAmount` (número, ej: "50 dólares no autorizado")

**Fulfillment**: Mapear a `ReportFraud` (mismo flujo de downstream)

---

### 3. **BlockCard** (Nuevo)
**Propósito**: Solicitud explícita de bloqueo de tarjeta.

**Utterances**:
- "bloquea mi tarjeta"
- "quiero bloquear mi tarjeta"
- "bloquear mi cuenta"
- "deshabilitar mi tarjeta"
- "desactiva mi tarjeta"
- "quiero que bloquees mi tarjeta"
- "bloquea mi tarjeta por seguridad"

**Slot**: Opcional - `CardType` (débito, crédito, virtual)

**Fulfillment**: Ir directamente a "Iniciar Bloqueo Tarjeta" (saltando "¿Reconoces este cargo?")

---

### 4. **SuspiciousTransaction** (Nuevo)
**Propósito**: Variación enfocada en transacciones sospechosas.

**Utterances**:
- "hay una transacción sospechosa"
- "movimiento sospechoso"
- "cargo sospechoso"
- "transacción extraña"
- "operación sospechosa"
- "veo un cargo que no reconozco"
- "hay cargos raros"
- "transacción anormal"

**Slot**: Opcional - `Merchant` (ej: "Apple Store")

**Fulfillment**: Mapear a `ReportFraud`

---

### 5. **ReportFraudVariant** (Nuevo)
**Propósito**: Variaciones del término "fraude" más específicas.

**Utterances**:
- "reportar un cargo fraudulento"
- "tengo fraude"
- "actividad fraudulenta en mi cuenta"
- "fraude en mi tarjeta"
- "detecté fraude"
- "creo que me han defraudado"
- "hay fraude aquí"
- "parece fraude"

**Slot**: None

**Fulfillment**: Mapear a `ReportFraud`

---

## Estrategia de Mapeo en el Flujo V3

### Opción A: Todos a `ReportFraud` (Recomendado)
```
Lex Bienvenida (Reconoce todos los intents anteriores)
  ├─ ReportFraud → NextAction = "Solicitar ID Cliente"
  ├─ ReportUnauthorized → NextAction = "Solicitar ID Cliente"
  ├─ BlockCard → NextAction = "Solicitar ID Cliente" (se puede mejora después)
  ├─ SuspiciousTransaction → NextAction = "Solicitar ID Cliente"
  └─ ReportFraudVariant → NextAction = "Solicitar ID Cliente"
```

### Opción B: Rutas Diferenciadas (Futuro)
```
Lex Bienvenida
  ├─ ReportFraud / ReportUnauthorized / SuspiciousTransaction / ReportFraudVariant
  │   → NextAction = "Solicitar ID Cliente" (flujo estándar)
  │
  └─ BlockCard → NextAction = "Iniciar Bloqueo Tarjeta" (saltando validaciones previas)
```

Para V3, **se recomienda Opción A** (mapeo unificado) para mantener la estabilidad.

---

## Implementación

### Paso 1: Validar con Script (Sin Cambios)
```bash
cd /Users/daryelispinate/Desktop/proyectosIVCISA/connect-demo-infra
./scripts/add-fraud-intents.sh --profile sandbox --region us-east-1
```

Esto **lista** los intents actuales sin hacer cambios.

### Paso 2: Crear Intents con Python
```bash
python3 scripts/create_lex_intents.py \
  --region us-east-1 \
  --profile sandbox \
  --bot-id NXHHCKVHHM \
  --bot-version DRAFT \
  --locale-id es_419
```

**⚠️ IMPORTANTE**: Este script solo funciona si tienes permisos `lex:CreateIntent` y boto3 ≥ 1.26.0.

### Paso 3: Compilar el Bot
1. Accede a [AWS Lex Console](https://console.aws.amazon.com/lexv2/)
2. Selecciona **BankingFraudBot**
3. Haz clic en **Build**
4. Espera a que compile (suele tardar 2-3 minutos)

### Paso 4: Actualizar el Alias
Una vez compilado:
1. Ve a **Aliases** en el panel izquierdo
2. Edita **SandboxBanking** (ZSII5DJKMX)
3. Selecciona la versión compilada más reciente
4. Guarda los cambios

### Paso 5: Verificar en el Flujo
El flujo V3 (`banking-v3.json`) ya está configurado para reconocer cualquier intent que retorne en el bloque `ConnectParticipantWithLexBot`. No hay cambios necesarios en el flujo.

---

## Validation

### Pruebas Manuales (Chat en Connect)
1. Inicia un chat con el flujo V3
2. Prueba cada utterance de los intents nuevos
3. Verifica que todas conduzcan a "Solicitar ID Cliente"

### Pruebas Automatizadas (Futuro)
Se puede crear un test harness con boto3:
```python
lex_client.recognize_text(
    botId='NXHHCKVHHM',
    botAliasId='ZSII5DJKMX',
    localeId='es_419',
    sessionId='test-session-123',
    text='bloquea mi tarjeta'  # Test utterance
)
# Verificar que retorna 'BlockCard' o 'ReportFraud'
```

---

## Cambios en Terraform (Ninguno)

Los intents de Lex **no se pueden gestionar vía Terraform** (el provider de AWS no lo soporta aún). Se gestionan manualmente o vía scripts Python/CLI.

Si en el futuro Terraform agrega soporte:
- Mover a `infra/modules/lex/` (módulo nuevo)
- Parametrizar intents como `var.lex_intents` (map)
- Versionar bot y alias automáticamente

---

## Timeline

| Fecha | Hito |
|---|---|
| 2026-10-11 | ✅ Especificación completada |
| 2026-10-11 | Scripts creados (`add-fraud-intents.sh`, `create_lex_intents.py`) |
| 2026-10-12 | Intents creados en consola o via script Python |
| 2026-10-12 | Bot compilado y alias actualizado |
| 2026-10-12 | Pruebas manuales en chat/voz |
| 2026-10-13 | Validación en producción (si aplica) |

---

## Rollback / Contingencia

Si los nuevos intents causan problemas:
1. **Versión anterior**: Cambia el alias `SandboxBanking` a la versión previa
2. **Eliminar intents**: Desde la consola, borra los intents nuevos
3. **Recompila**: Build → usa version anterior

No hay daño a datos; es solo un cambio de configuración.

---

## Notas Adicionales

### Consideraciones Lingüísticas
- Locale `es-419` cubre: México, centroamérica, parte de Sudamérica
- Los utterances están optimizados para este dialecto
- Para España (`es-ES`), se necesitaría revisar terminología (ej: "tarjeta" es igual, pero "cuenta" vs "cuenta bancaria")

### Mejoras Futuras
1. **NLU avanzada**: Entrenar slots específicos (monto, comercio, tipo de fraude)
2. **Sentiment analysis**: Detectar urgencia o frustración en el texto
3. **Multi-turn dialogs**: Clarificación antes de proceder (ej: "¿Qué tipo de fraude?")
4. **Fallback a agente**: Si el bot no entiende, transferir directamente

---

## Referencias

- [AWS Lex V2 Intent Docs](https://docs.aws.amazon.com/lexv2/latest/developerguide/managing-intents.html)
- [boto3 LexModelsV2 API](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/lexv2-models.html)
- Contexto del proyecto: `.kiro/contexto-v3.md`
- Especificación de casos: `.kiro/v3-cases-fraude-bancario.md`

---

**Autor**: Kiro  
**Última actualización**: 2026-10-11  
**Estado**: 🟡 En revisión
