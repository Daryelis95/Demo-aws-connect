Feedback - Amazon Connect de Daryelis

Como caso de negocio, el diseño aborda tres dolores de cabeza críticos en la banca minorista: costo por llamada, tiempo de resolución (AHT) y experiencia en momentos de alta fricción (fraude).
Análisis del Caso de Negocio

Defensa de Contención (Deflection Rate): Automatiza la fase más repetitiva del proceso (autenticación contextual, identificación del cargo y bloqueo inmediato), reduciendo la carga operativa en el Contact Center entre un 30% y un 40% en casos de fraude.
Mitigación del Riesgo Financiero: El bloqueo inmediato mediante la Lambda blockCard reduce la ventana de exposición a nuevos cargos fraudulentos de minutos/horas a segundos.
Reducción de AHT y Frictionless Handoff: Si la llamada escala a un agente humano, este no pierde tiempo preguntando "¿Qué le pasó?" o "¿Cuál es su tarjeta?". El contexto (journey_type, issue_summary, pending_request) llega precargado en el Screen Pop de Amazon Connect.
¿Cómo pulirlo para llevarlo a un nivel Enterprise (V2)?
Para transformar este prototipo en una arquitectura más refinada, te sugiero ajustar cinco áreas clave:
1. Seguridad e Identificación (STEP-UP Auth)

Validación de Identidad Obligatoria: Antes de ejecutar getTransactions o revelar que la compra fue en "Electronics Store por $850", se debe validar la identidad (OTP vía SMS/Push notification o verificación PIN/Biometría de voz en Connect). Revelar datos transaccionales sin autenticar expone información sensible (PII/PCI).
2. Lógica del Backend e Integración (DynamoDB & Lambda)

Idempotencia en el Bloqueo: La función blockCard debe ser idempotente. Si el cliente presiona o dice "Sí" varias veces o hay un retry por timeout de red, la Lambda no debe fallar ni duplicar eventos en auditoría.
Auditoría e Inmutabilidad en DynamoDB: Toda interacción (respuestas del cliente, hash de tarjeta, timestamps y resultado de la Lambda) debe registrarse en una tabla de auditoría en DynamoDB para cumplimiento normativo (PCI-DSS) y disputas posteriores.
3. Experiencia de Usuario (NLU & Fallbacks con Lex v2)

Manejo de Intentos Fallidos (No-Match / No-Input): Si el cliente dice algo ambiguous (ej. "Creo que fue mi esposa"), el bot debe tener un flujo de clarificación (máximo 2 reintentos antes de derivar a un humano) para evitar que la llamada quede en un bucle.
Confirmaciones Explícitas: El bloqueo de tarjeta es una acción irreversible por autoservicio. El bot debe requerir una confirmación alta (ej. "Responde SÍ para confirmar el bloqueo definitivo de la tarjeta terminada en 4455").
4. Gestión de Errores y Resiliencia (Circuit Breakers)

Manejo de Timeouts de API: Si la Lambda de getTransactions o blockCard demora más de 8 segundos (por ejemplo, por latencia del Core Bancario), Connect debe capturar el error elegantemente (Error Fallback) y transferir al especialista sin colgar ni decir "Ocurrió un error técnico".
5. Transferencia Avanzada y Enrutamiento (Routing & Screen Pop)

Priorización de Colas: Las llamadas donde suspicious == true y action_completed == Tarjeta bloqueada deben entrar a una cola de alta prioridad en Connect (Skill: Fraudes - Disputas Urgent).
Manejo de Atributos Limitados: Amazon Connect tiene límites en el tamaño de los User Defined Contact Attributes. Asegúrate de pasar valores concisos en issue_summary para no truncar la carga del Screen Pop.