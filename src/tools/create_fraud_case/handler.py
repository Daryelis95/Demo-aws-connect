"""
Lambda: create_fraud_case
Dominio: Banca — V3

Descripción:
Crea un expediente de fraude en Amazon Connect Cases, lo vincula al contacto
activo y registra la operación en DynamoDB para deduplicación.

Entrada desde Amazon Connect:
{
    "Details": {
        "ContactData": {
            "ContactId":    "<contactId>",
            "InstanceARN":  "arn:aws:connect:us-east-1:...:instance/..."
        },
        "Parameters": {
            "customerId":    "CUS-2001",
            "transactionId": "TXN-9002",
            "cardReference": "****4455",
            "blockResult":   "BLOCKED",
            "consent":       "true",
            "blockedAt":     "2026-10-09T14:00:00Z",
            "operationId":   "FRAUD-CUS-2001-TXN-9002"
        }
    }
}

Respuesta STRING_MAP:
{
    "success":       "true",
    "caseId":        "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "caseArn":       "arn:aws:cases:...",
    "caseCreated":   "true",
    "contactLinked": "true",
    "errorCode":     ""
}
"""

import json
import logging
import os
from datetime import datetime, timezone

import boto3


# ============================================================
# CONFIGURACIÓN
# ============================================================

logger = logging.getLogger()
logger.setLevel(os.getenv("LOG_LEVEL", "INFO"))

AWS_REGION = os.getenv("AWS_REGION_NAME", "us-east-1")

dynamodb         = boto3.resource("dynamodb", region_name=AWS_REGION)
cases_client     = boto3.client("connectcases", region_name=AWS_REGION)
profiles_client  = boto3.client("customer-profiles", region_name=AWS_REGION)
connect_client   = boto3.client("connect", region_name=AWS_REGION)

TABLE_NAME                   = os.environ["DYNAMODB_TABLE_NAME"]
CASES_DOMAIN_ID              = os.environ["CASES_DOMAIN_ID"]
CASES_TEMPLATE_ID            = os.environ["CASES_TEMPLATE_ID"]
CUSTOMER_PROFILES_DOMAIN     = os.environ["CUSTOMER_PROFILES_DOMAIN"]
CONNECT_INSTANCE_ID          = os.environ.get("CONNECT_INSTANCE_ID", "")
TASK_TEMPLATE_ID             = os.environ.get("TASK_TEMPLATE_ID", "")

# JSON con el mapa de field_name → fieldId
# Ejemplo: '{"customerId":"uuid","transactionId":"uuid",...}'
CASES_FIELD_IDS_RAW          = os.environ.get("CASES_FIELD_IDS", "{}")

try:
    CASES_FIELD_IDS = json.loads(CASES_FIELD_IDS_RAW)
except json.JSONDecodeError:
    CASES_FIELD_IDS = {}


# ============================================================
# HELPERS
# ============================================================

def get_contact_data(event):
    """Extrae ContactId e InstanceARN desde el evento de Connect."""
    contact_data = event.get("Details", {}).get("ContactData", {})
    return (
        contact_data.get("ContactId", ""),
        contact_data.get("InstanceARN", "")
    )


def get_parameters(event):
    """Lee parámetros desde Connect o desde invocación directa."""
    connect_params = event.get("Details", {}).get("Parameters", {})
    return connect_params if connect_params else event


def connect_response(success, case_id="", case_arn="", case_created="false",
                     contact_linked="false", error_code=""):
    """STRING_MAP plano para Amazon Connect."""
    return {
        "success":       str(success).lower(),
        "caseId":        str(case_id or ""),
        "caseArn":       str(case_arn or ""),
        "caseCreated":   str(case_created),
        "contactLinked": str(contact_linked),
        "errorCode":     str(error_code or "")
    }


def field_value(field_name, value):
    """Construye el formato de campo que espera la API de Cases."""
    field_id = CASES_FIELD_IDS.get(field_name)
    if not field_id or not value:
        return None
    return {
        "id":    field_id,
        "value": {"stringValue": str(value)}
    }


def build_case_fields(params, contact_id, case_title):
    """
    Construye la lista de campos para CreateCase / UpdateCase.
    Solo incluye campos que tienen fieldId configurado y valor no vacío.
    El campo de sistema 'title' siempre va primero — es requerido por la plantilla.
    """
    fields = []

    # 'title' es un campo de sistema con fieldId literal "title"
    if case_title:
        fields.append({"id": "title", "value": {"stringValue": str(case_title)}})

    custom_field_map = {
        "customerId":    params.get("customerId", ""),
        "transactionId": params.get("transactionId", ""),
        "cardReference": params.get("cardReference", ""),
        "blockResult":   params.get("blockResult", ""),
        "blockedAt":     params.get("blockedAt", ""),
        "consent":       params.get("consent", ""),
        "operationId":   params.get("operationId", ""),
        "priority":      "HIGH",
        "contactId":     contact_id,
    }

    for name, value in custom_field_map.items():
        fv = field_value(name, value)
        if fv:
            fields.append(fv)

    return fields


def search_customer_profile(customer_id):
    """
    Busca el perfil en Customer Profiles por AccountNumber.
    Devuelve el ProfileId o None si no se encuentra.
    """
    try:
        response = profiles_client.search_profiles(
            DomainName=CUSTOMER_PROFILES_DOMAIN,
            KeyName="_account",
            Values=[customer_id]
        )
        items = response.get("Items", [])
        if items:
            return items[0].get("ProfileId")
    except Exception:
        logger.warning(json.dumps({
            "event": "search_profiles_failed",
            "customer_id": customer_id
        }))
    return None


def create_followup_task(correlation_id, case_id, customer_id,
                         transaction_id, card_reference, block_result, operation_id):
    """
    Crea una tarea de seguimiento en Amazon Connect vinculada al caso de fraude.
    No es crítica — si falla, el caso ya fue creado y se loggea el error.
    Solo se ejecuta si CONNECT_INSTANCE_ID y TASK_TEMPLATE_ID están configurados.
    """
    if not CONNECT_INSTANCE_ID or not TASK_TEMPLATE_ID:
        logger.warning(json.dumps({
            "event":          "task_skipped_missing_config",
            "correlation_id": correlation_id
        }))
        return False

    # El nombre de la tarea es lo primero que ve el agente en su panel
    task_name = f"Seguimiento fraude {customer_id} — {card_reference}"

    try:
        connect_client.start_task_contact(
            InstanceId=CONNECT_INSTANCE_ID,
            Name=task_name,
            TaskTemplateId=TASK_TEMPLATE_ID,
            Description=(
                f"Caso: {case_id} | Cliente: {customer_id} | "
                f"Tarjeta: {card_reference} | Resultado: {block_result} | "
                f"Operación: {operation_id}"
            ),
            Attributes={
                "name":          task_name,
                "caseId":        case_id,
                "customerId":    customer_id,
                "blockResult":   block_result,
                "cardReference": card_reference,
                "operationId":   operation_id
            }
        )
        logger.info(json.dumps({
            "event":          "followup_task_created",
            "correlation_id": correlation_id,
            "case_id":        case_id,
            "operation_id":   operation_id
        }))
        return True

    except Exception as exc:
        logger.warning(json.dumps({
            "event":          "followup_task_failed",
            "correlation_id": correlation_id,
            "case_id":        case_id,
            "error":          str(exc)
        }))
        return False


# ============================================================
# LAMBDA HANDLER
# ============================================================

def lambda_handler(event, context):

    correlation_id = context.aws_request_id

    logger.info(json.dumps({
        "event":          "create_fraud_case_invoked",
        "correlation_id": correlation_id,
        "source":         "amazon_connect" if "Details" in event else "direct"
    }))

    # --------------------------------------------------------
    # 1. Extraer datos del contacto y parámetros
    # --------------------------------------------------------

    contact_id, instance_arn = get_contact_data(event)
    parameters               = get_parameters(event)

    customer_id    = str(parameters.get("customerId", "")).strip()
    transaction_id = str(parameters.get("transactionId", "")).strip()
    card_reference = str(parameters.get("cardReference", "")).strip()
    block_result   = str(parameters.get("blockResult", "")).strip()
    consent        = str(parameters.get("consent", "false")).strip().lower()
    blocked_at     = str(parameters.get("blockedAt", "")).strip()
    operation_id   = str(parameters.get("operationId", "")).strip()

    logger.info(json.dumps({
        "event":          "create_fraud_case_params",
        "correlation_id": correlation_id,
        "customer_id":    customer_id,
        "transaction_id": transaction_id,
        "operation_id":   operation_id,
        "block_result":   block_result,
        "has_contact_id": bool(contact_id)
    }))

    # --------------------------------------------------------
    # 2. Validaciones mínimas
    # --------------------------------------------------------

    if not customer_id or not transaction_id:
        logger.error(json.dumps({
            "event":      "create_fraud_case_validation_error",
            "error_code": "MISSING_REQUIRED_PARAMS"
        }))
        return connect_response(
            success=False,
            error_code="MISSING_REQUIRED_PARAMS"
        )

    if not operation_id:
        operation_id = f"FRAUD-{customer_id}-{transaction_id}"

    # --------------------------------------------------------
    # 3. Deduplicación — verificar si ya existe en DynamoDB
    # --------------------------------------------------------

    table = dynamodb.Table(TABLE_NAME)
    ledger_pk = f"CUSTOMER#{customer_id}"
    ledger_sk = f"FRAUDOP#{operation_id}"

    existing_case_id  = None
    existing_case_arn = None

    try:
        ledger_resp = table.get_item(
            Key={"PK": ledger_pk, "SK": ledger_sk}
        )
        ledger_item = ledger_resp.get("Item", {})

        if ledger_item.get("case_status") == "CASE_CREATED":
            existing_case_id  = ledger_item.get("case_id")
            existing_case_arn = ledger_item.get("case_arn")

    except Exception:
        logger.warning(json.dumps({
            "event":          "create_fraud_case_ledger_read_error",
            "correlation_id": correlation_id
        }))
        # No bloqueamos si no podemos leer el ledger — seguimos adelante

    if existing_case_id:
        logger.info(json.dumps({
            "event":          "case_reused",
            "correlation_id": correlation_id,
            "case_id":        existing_case_id,
            "operation_id":   operation_id
        }))
        return connect_response(
            success=True,
            case_id=existing_case_id,
            case_arn=existing_case_arn or "",
            case_created="false",
            contact_linked="false"
        )

    # --------------------------------------------------------
    # 4. Construir campos del caso
    # --------------------------------------------------------

    # Título del caso — siempre requerido (campo de sistema 'title')
    case_title = f"Fraude {customer_id} - {transaction_id}"

    case_fields = build_case_fields(
        {
            "customerId":    customer_id,
            "transactionId": transaction_id,
            "cardReference": card_reference,
            "blockResult":   block_result,
            "consent":       consent,
            "blockedAt":     blocked_at,
            "operationId":   operation_id,
        },
        contact_id,
        case_title
    )

    # --------------------------------------------------------
    # 5. Crear el caso en Connect Cases
    # --------------------------------------------------------

    case_id  = None
    case_arn = None

    try:
        create_resp = cases_client.create_case(
            domainId=CASES_DOMAIN_ID,
            templateId=CASES_TEMPLATE_ID,
            fields=case_fields,
            clientToken=operation_id       # idempotencia nativa de la API
        )
        case_id  = create_resp.get("caseId")
        case_arn = create_resp.get("caseArn")

    except cases_client.exceptions.ConflictException:
        # clientToken ya existe — caso creado en un reintento anterior
        logger.warning(json.dumps({
            "event":          "case_conflict_token",
            "correlation_id": correlation_id,
            "operation_id":   operation_id
        }))
        # Intentamos recuperar el caseId existente desde el ledger
        # (puede que el write de DynamoDB no llegó antes)
        try:
            ledger_retry = table.get_item(Key={"PK": ledger_pk, "SK": ledger_sk})
            item_retry   = ledger_retry.get("Item", {})
            case_id  = item_retry.get("case_id", "")
            case_arn = item_retry.get("case_arn", "")
        except Exception:
            pass

        if case_id:
            return connect_response(
                success=True,
                case_id=case_id,
                case_arn=case_arn or "",
                case_created="false",
                contact_linked="false"
            )
        # Si no tenemos el ID, reportar fallo
        return connect_response(
            success=False,
            error_code="CASE_CONFLICT_UNRESOLVED"
        )

    except Exception as exc:
        logger.error(json.dumps({
            "event":          "case_create_failed",
            "correlation_id": correlation_id,
            "operation_id":   operation_id,
            "error":          str(exc)
        }))
        return connect_response(
            success=False,
            error_code="CASE_CREATE_FAILED"
        )

    if not case_id:
        logger.error(json.dumps({
            "event":          "case_create_no_id",
            "correlation_id": correlation_id
        }))
        return connect_response(
            success=False,
            error_code="CASE_CREATE_FAILED"
        )

    # --------------------------------------------------------
    # 6. Registrar en DynamoDB (ledger para deduplicación)
    # --------------------------------------------------------

    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    try:
        table.put_item(Item={
            "PK":              ledger_pk,
            "SK":              ledger_sk,
            "customer_id":     customer_id,
            "transaction_id":  transaction_id,
            "operation_id":    operation_id,
            "case_id":         case_id,
            "case_arn":        case_arn,
            "case_status":     "CASE_CREATED",
            "block_result":    block_result,
            "contact_id":      contact_id,
            "created_at":      now
        })
    except Exception:
        # El caso ya fue creado — logueamos pero no fallamos
        logger.warning(json.dumps({
            "event":          "case_ledger_write_failed",
            "correlation_id": correlation_id,
            "case_id":        case_id
        }))

    # --------------------------------------------------------
    # 7. Vincular contacto al caso (CreateRelatedItem)
    # --------------------------------------------------------

    contact_linked = "false"

    if contact_id and instance_arn:
        # El ARN del contacto se construye desde el InstanceARN + ContactId
        contact_arn = f"{instance_arn}/contact/{contact_id}"

        try:
            cases_client.create_related_item(
                domainId=CASES_DOMAIN_ID,
                caseId=case_id,
                type="Contact",
                content={
                    "contact": {
                        "contactArn": contact_arn
                    }
                }
            )
            contact_linked = "true"

        except Exception:
            logger.warning(json.dumps({
                "event":          "contact_link_failed",
                "correlation_id": correlation_id,
                "case_id":        case_id,
                "contact_id":     contact_id
            }))
            # El caso está creado — el link del contacto no es crítico

    # --------------------------------------------------------
    # 8. Log de éxito y respuesta
    # --------------------------------------------------------

    logger.info(json.dumps({
        "event":           "case_created",
        "correlation_id":  correlation_id,
        "case_id":         case_id,
        "operation_id":    operation_id,
        "customer_id":     customer_id,
        "transaction_id":  transaction_id,
        "block_result":    block_result,
        "contact_linked":  contact_linked
    }))

    # --------------------------------------------------------
    # 9. Tarea de seguimiento — no crítica, no bloquea la respuesta
    # --------------------------------------------------------

    # Solo lanza la tarea cuando hay un bloqueo real o no autorizado.
    # NOT_APPLICABLE = transacción reconocida → sin tarea de seguimiento.
    if block_result != "NOT_APPLICABLE":
        create_followup_task(
            correlation_id = correlation_id,
            case_id        = case_id,
            customer_id    = customer_id,
            transaction_id = transaction_id,
            card_reference = card_reference,
            block_result   = block_result,
            operation_id   = operation_id
        )

    return connect_response(
        success=True,
        case_id=case_id,
        case_arn=case_arn,
        case_created="true",
        contact_linked=contact_linked
    )
