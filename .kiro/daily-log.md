# Daily Log

---

## 12/10/2026

**Demo bancaria antifraude — Progreso V3**
- ✅ Número telefónico movido a flujo V3 (completado)
- 🟡 Intents Lex pendientes: ReportUnauthorized, BlockCard, SuspiciousTransaction, ReportFraudVariant
- 🟡 Compilación de bot Lex pendiente
- 🟡 Actualización de alias SandboxBanking pendiente
- Actualizar contexto-general.md para reflejar progreso

---

## 11/10/2026

**Demo bancaria antifraude — Expansión de Intents de Lex**
- Crear especificación completa para nuevos intents de fraude en `lex-intents-specification.md`
- Implementar script de validación: `scripts/add-fraud-intents.sh` (lista intents actuales sin cambios)
- Implementar script Python con boto3: `scripts/create_lex_intents.py` (crea/actualiza intents en DRAFT)
- Documentar intents propuestos:
  - ✅ ReportFraud (existente, validar)
  - 🆕 ReportUnauthorized (movimiento no autorizado)
  - 🆕 BlockCard (bloqueo de tarjeta explícito)
  - 🆕 SuspiciousTransaction (transacción sospechosa)
  - 🆕 ReportFraudVariant (variaciones de fraude)
- Crear documento `infra/modules/lex/FUTURE_SUPPORT.md` con plan de soporte en Terraform (actualmente bloqueado por issue #33934)
- Estrategia: Mapear todos los intents nuevos a "Solicitar ID Cliente" (Opción A - unificada)
- **Status**: 🟡 Ready para activación - scripts creados, intents documentados, implementación pendiente en consola o vía script Python

---

## 08/10/2026

**Demo bancaria antifraude**
- Levantar y validar demo de Grupo Comida en Amazon Connect
- Exportar y versionar flujo antifraude actual como referencia base
- Crear flujo V3 del proceso de fraude con mejoras de trazabilidad y expediente
- Agregar cola de fraude de alta prioridad al enrutamiento de Connect
- Configurar variables e infraestructura para integración con Amazon Connect Cases
- Realizar ajustes en la demo bancaria V3 tomando como base los patrones y mejoras de la demo de Grupo Comida
- Documentar cambios pendientes de consola y próximos pasos de implementación

---

## 07/10/2026

**Demo bancaria antifraude**
- Validar flujo de fraude bancario en Amazon Connect e identificar mejoras
- Ajustar estrategia de reintentos de Lex y manejo de errores
- Revisar Lambda block-card y definir estándar de respuestas
- Definir mejoras en confirmación de bloqueo y contexto enviado al agente

**ZenCost — Aura Insights**
- Rediseño visual de cards
- Incorporar orbe animado
- Limpieza de UI: scope toggle, health ring y categoría

**Para el 08/10**
- Duplicar flujo actual como v2 e iniciar mejoras
- Validar flujo completo con llamada real
- ZenCost: ajustes de íconos y tipografía pendientes
