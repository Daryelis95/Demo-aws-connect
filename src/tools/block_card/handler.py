"""
Lambda: block_card
Dominio: Banca — V3

Descripción:
Bloquea una tarjeta bancaria (ACTIVE -> BLOCKED) en DynamoDB.
Compatible con Amazon Connect usando ResponseType=STRING_MAP.

Entrada desde Amazon Connect:
{
    "Details": {
        "Parameters": {
            "action":      "blockCard",
            "cardId":      "CARD-4455",
            "consent":     "true",
            "operationId": "FRAUD-CUS-2001-TXN-9002"
        }
    }
}

Respuesta hacia Amazon Connect (STRING_MAP):
{
    "success":        "true",
    "blockResult":    "BLOCKED",           # BLOCKED | ALREADY_BLOCKED | FAILED | NOT_AUTHORIZED
    "cardId":         "CARD-4455",
    "cardReference":  "****4455",
    "previousStatus": "ACTIVE",
    "newStatus":      "BLOCKED",
    "blockedAt":      "2026-10-09T14:00:00Z",
    "errorCode":      "",
    "message":        "La tarjeta terminada en 4455 fue bloqueada."
}
"""

import json
import logging
import os
from datetime import datetime, timezone

import boto3
from boto3.dynamodb.conditions import Key


# ============================================================
# Logging
# ============================================================

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))


# ============================================================
# AWS Clients
# ============================================================

AWS_REGION = os.environ.get("AWS_REGION_NAME", "us-east-1")

dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)


# ============================================================
# Environment variables
# ============================================================

TABLE_NAME      = os.environ["DYNAMODB_TABLE_NAME"]
BLOCKABLE_STATUSES = {"ACTIVE"}


# ============================================================
# Helpers
# ============================================================

def connect_response(
    success,
    block_result="FAILED",
    card_id="",
    card_reference="",
    previous_status="",
    new_status="",
    blocked_at="",
    error_code="",
    message=""
):
    """
    Amazon Connect STRING_MAP: JSON plano, todos los valores strings.
    """
    return {
        "success":        str(success).lower(),
        "blockResult":    str(block_result),
        "cardId":         str(card_id or ""),
        "cardReference":  str(card_reference or ""),
        "previousStatus": str(previous_status or ""),
        "newStatus":      str(new_status or ""),
        "blockedAt":      str(blocked_at or ""),
        "errorCode":      str(error_code or ""),
        "message":        str(message or ""),
    }


def get_parameters(event):
    """Lee parámetros desde Connect o desde invocación directa."""
    details = event.get("Details", {})
    if isinstance(details, dict):
        parameters = details.get("Parameters", {})
        if parameters:
            return parameters
    return event


def mask_card(card_id):
    """Devuelve los últimos 4 dígitos con máscara: ****4455"""
    suffix = card_id[-4:] if len(card_id) >= 4 else "????"
    return f"****{suffix}", suffix


# ============================================================
# Lambda Handler
# ============================================================

def lambda_handler(event, context):

    correlation_id = context.aws_request_id

    # Log de entrada sin PII — solo metadatos de la operación
    logger.info(json.dumps({
        "event":          "block_card_invoked",
        "correlation_id": correlation_id,
        "source":         "amazon_connect" if "Details" in event else "direct"
    }))

    # --------------------------------------------------------
    # 1. Obtener parámetros
    # --------------------------------------------------------

    parameters = get_parameters(event)

    card_id      = (parameters.get("cardId") or parameters.get("card_id") or "").strip()
    action       = (parameters.get("action") or "blockCard").strip()
    consent      = (parameters.get("consent") or "false").strip().lower()
    operation_id = (parameters.get("operationId") or parameters.get("operation_id") or "").strip()

    if not card_id:
        logger.warning(json.dumps({
            "event":          "block_card_validation_error",
            "correlation_id": correlation_id,
            "error_code":     "MISSING_CARD_ID"
        }))
        return connect_response(
            success=False,
            block_result="FAILED",
            error_code="MISSING_CARD_ID",
            message="No pude identificar la tarjeta."
        )

    card_reference, card_suffix = mask_card(card_id)

    # Si el cliente NO dio consentimiento, no procedemos
    if consent != "true":
        logger.info(json.dumps({
            "event":          "block_card_not_authorized",
            "correlation_id": correlation_id,
            "card_suffix":    card_suffix
        }))
        return connect_response(
            success=True,
            block_result="NOT_AUTHORIZED",
            card_id=card_id,
            card_reference=card_reference,
            error_code="",
            message="El cliente no autorizó el bloqueo de la tarjeta."
        )

    if action == "getCardStatus":
        # Acción de solo lectura para contingencia de timeout en el flujo
        return _get_card_status(correlation_id, card_id, card_reference, card_suffix)

    if action != "blockCard":
        return connect_response(
            success=False,
            block_result="FAILED",
            card_id=card_id,
            card_reference=card_reference,
            error_code="INVALID_ACTION",
            message="La operación solicitada no es válida."
        )

    # --------------------------------------------------------
    # 3. Consultar tarjeta en DynamoDB (GSI1)
    # --------------------------------------------------------

    table = dynamodb.Table(TABLE_NAME)

    try:
        response = table.query(
            IndexName="GSI1",
            KeyConditionExpression=Key("GSI1PK").eq(f"CARD#{card_id}")
        )
        items = response.get("Items", [])

    except Exception as exc:
        logger.error(json.dumps({
            "event":          "block_card_db_error",
            "correlation_id": correlation_id,
            "error_code":     "DATABASE_ERROR"
        }))
        return connect_response(
            success=False,
            block_result="FAILED",
            card_id=card_id,
            card_reference=card_reference,
            error_code="DATABASE_ERROR",
            message="No fue posible consultar la tarjeta."
        )

    if not items:
        logger.warning(json.dumps({
            "event":          "block_card_not_found",
            "correlation_id": correlation_id,
            "error_code":     "CARD_NOT_FOUND"
        }))
        return connect_response(
            success=False,
            block_result="FAILED",
            card_id=card_id,
            card_reference=card_reference,
            error_code="CARD_NOT_FOUND",
            message="No se encontró la tarjeta indicada."
        )

    item           = items[0]
    pk             = item["PK"]
    sk             = item["SK"]
    current_status = item.get("status", "")

    # --------------------------------------------------------
    # 4. Validar estado actual
    # --------------------------------------------------------

    if current_status == "BLOCKED":
        logger.info(json.dumps({
            "event":          "block_card_already_blocked",
            "correlation_id": correlation_id,
            "card_suffix":    card_suffix
        }))
        return connect_response(
            success=True,
            block_result="ALREADY_BLOCKED",
            card_id=card_id,
            card_reference=card_reference,
            previous_status="BLOCKED",
            new_status="BLOCKED",
            message=f"La tarjeta terminada en {card_suffix} ya se encuentra bloqueada."
        )

    if current_status not in BLOCKABLE_STATUSES:
        return connect_response(
            success=False,
            block_result="FAILED",
            card_id=card_id,
            card_reference=card_reference,
            previous_status=current_status,
            new_status=current_status,
            error_code="INVALID_CARD_STATUS",
            message=f"La tarjeta no puede ser bloqueada. Estado actual: {current_status}."
        )

    # --------------------------------------------------------
    # 5. Ejecutar bloqueo en DynamoDB
    # --------------------------------------------------------

    blocked_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # Construir update expression — agrega operation_id si se proporcionó
    update_expr = "SET #s = :new_status, blocked_at = :ts"
    expr_values = {
        ":new_status": "BLOCKED",
        ":ts":         blocked_at,
        ":expected":   current_status,
    }

    if operation_id:
        update_expr += ", operation_id = :op_id"
        expr_values[":op_id"] = operation_id

    try:
        table.update_item(
            Key={"PK": pk, "SK": sk},
            UpdateExpression=update_expr,
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues=expr_values,
            ConditionExpression="#s = :expected"
        )

    except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
        logger.warning(json.dumps({
            "event":          "block_card_conditional_failed",
            "correlation_id": correlation_id,
            "card_suffix":    card_suffix
        }))
        return connect_response(
            success=False,
            block_result="FAILED",
            card_id=card_id,
            card_reference=card_reference,
            previous_status=current_status,
            error_code="CARD_STATUS_CHANGED",
            message="El estado de la tarjeta cambió durante la operación. Intenta nuevamente."
        )

    except Exception:
        logger.exception(json.dumps({
            "event":          "block_card_update_error",
            "correlation_id": correlation_id,
            "error_code":     "BLOCK_CARD_ERROR"
        }))
        return connect_response(
            success=False,
            block_result="FAILED",
            card_id=card_id,
            card_reference=card_reference,
            previous_status=current_status,
            error_code="BLOCK_CARD_ERROR",
            message="No fue posible bloquear la tarjeta."
        )

    # --------------------------------------------------------
    # 6. Respuesta exitosa — mensaje fijo (sin Bedrock en camino crítico)
    # --------------------------------------------------------

    logger.info(json.dumps({
        "event":          "block_card_success",
        "correlation_id": correlation_id,
        "card_suffix":    card_suffix,
        "previous_status": current_status,
        "new_status":     "BLOCKED",
        "operation_id":   operation_id or ""
    }))

    return connect_response(
        success=True,
        block_result="BLOCKED",
        card_id=card_id,
        card_reference=card_reference,
        previous_status=current_status,
        new_status="BLOCKED",
        blocked_at=blocked_at,
        error_code="",
        message=f"La tarjeta terminada en {card_suffix} fue bloqueada correctamente."
    )


# ============================================================
# Acción auxiliar: getCardStatus (solo lectura)
# ============================================================

def _get_card_status(correlation_id, card_id, card_reference, card_suffix):
    """
    Devuelve el estado actual de la tarjeta sin modificar nada.
    Se usa como contingencia cuando el flujo principal tiene timeout.
    """
    table = dynamodb.Table(TABLE_NAME)

    try:
        response = table.query(
            IndexName="GSI1",
            KeyConditionExpression=Key("GSI1PK").eq(f"CARD#{card_id}")
        )
        items = response.get("Items", [])

    except Exception:
        logger.error(json.dumps({
            "event":          "get_card_status_db_error",
            "correlation_id": correlation_id,
            "error_code":     "DATABASE_ERROR"
        }))
        return connect_response(
            success=False,
            block_result="FAILED",
            card_id=card_id,
            card_reference=card_reference,
            error_code="DATABASE_ERROR",
            message="No fue posible consultar el estado de la tarjeta."
        )

    if not items:
        return connect_response(
            success=False,
            block_result="FAILED",
            card_id=card_id,
            card_reference=card_reference,
            error_code="CARD_NOT_FOUND",
            message="No se encontró la tarjeta indicada."
        )

    current_status = items[0].get("status", "UNKNOWN")
    blocked_at     = items[0].get("blocked_at", "")

    logger.info(json.dumps({
        "event":          "get_card_status_success",
        "correlation_id": correlation_id,
        "card_suffix":    card_suffix,
        "status":         current_status
    }))

    return connect_response(
        success=True,
        block_result="ALREADY_BLOCKED" if current_status == "BLOCKED" else "FAILED",
        card_id=card_id,
        card_reference=card_reference,
        previous_status=current_status,
        new_status=current_status,
        blocked_at=blocked_at,
        message=f"Estado actual de la tarjeta terminada en {card_suffix}: {current_status}."
    )
