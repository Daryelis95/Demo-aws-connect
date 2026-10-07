"""
Lambda: block_card
Dominio: Banca

Descripción:
Bloquea una tarjeta bancaria (ACTIVE -> BLOCKED) en DynamoDB.
Compatible con Amazon Connect usando ResponseType=STRING_MAP.

Entrada desde Amazon Connect:

{
    "Details": {
        "Parameters": {
            "cardId": "CARD-4455",
            "action": "blockCard"
        }
    }
}

Respuesta hacia Amazon Connect:

{
    "success": "true",
    "cardId": "CARD-4455",
    "previousStatus": "ACTIVE",
    "newStatus": "BLOCKED",
    "blockedAt": "...",
    "message": "..."
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

dynamodb = boto3.resource(
    "dynamodb",
    region_name=AWS_REGION
)

bedrock = boto3.client(
    "bedrock-runtime",
    region_name=AWS_REGION
)


# ============================================================
# Environment variables
# ============================================================

TABLE_NAME = os.environ["DYNAMODB_TABLE_NAME"]

BEDROCK_MODEL_ID = os.environ.get(
    "BEDROCK_MODEL_ID",
    "anthropic.claude-sonnet-4-6"
)


BLOCKABLE_STATUSES = {"ACTIVE"}


# ============================================================
# Helpers
# ============================================================

def connect_response(
    success,
    card_id="",
    previous_status="",
    new_status="",
    blocked_at="",
    message="",
    error=""
):
    """
    Amazon Connect STRING_MAP requiere:
    - JSON plano
    - sin objetos anidados
    - todos los valores deben ser strings
    """

    return {
        "success": str(success).lower(),
        "cardId": str(card_id or ""),
        "previousStatus": str(previous_status or ""),
        "newStatus": str(new_status or ""),
        "blockedAt": str(blocked_at or ""),
        "message": str(message or ""),
        "error": str(error or "")
    }


def get_parameters(event):
    """
    Permite ejecutar la Lambda tanto desde Amazon Connect
    como manualmente desde la consola de Lambda.
    """

    # Amazon Connect
    details = event.get("Details", {})

    if isinstance(details, dict):
        parameters = details.get("Parameters", {})

        if parameters:
            return parameters

    # Ejecución directa para testing
    return event


def invoke_bedrock(card_suffix, blocked_at):
    """
    Genera un mensaje conversacional de confirmación.

    Nunca envía el número completo de la tarjeta a Bedrock.
    """

    prompt = (
        "Eres un asistente virtual de atención al cliente de un banco. "
        "Responde siempre en español, de forma breve, clara y profesional. "
        "Nunca menciones números completos de tarjetas.\n\n"
        f"La tarjeta terminada en {card_suffix} fue bloqueada "
        f"correctamente el {blocked_at}.\n\n"
        "Genera un mensaje para comunicar al cliente que la tarjeta "
        "fue bloqueada correctamente, que ya no podrá utilizarse para "
        "nuevas transacciones y que puede solicitar una tarjeta de "
        "reemplazo."
    )

    body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 180,
        "temperature": 0.2,
        "messages": [
            {
                "role": "user",
                "content": prompt
            }
        ]
    }

    response = bedrock.invoke_model(
        modelId=BEDROCK_MODEL_ID,
        contentType="application/json",
        accept="application/json",
        body=json.dumps(body)
    )

    response_body = json.loads(
        response["body"].read()
    )

    return response_body["content"][0]["text"].strip()


# ============================================================
# Lambda Handler
# ============================================================

def lambda_handler(event, context):

    correlation_id = context.aws_request_id

    logger.info(json.dumps({
        "correlation_id": correlation_id,
        "tool": "block_card",
        "event_source": "amazon_connect"
        if "Details" in event
        else "direct"
    }))

    # --------------------------------------------------------
    # Obtener parámetros
    # --------------------------------------------------------

    parameters = get_parameters(event)

    card_id = (
        parameters.get("cardId")
        or parameters.get("card_id")
        or ""
    ).strip()

    action = (
        parameters.get("action")
        or "blockCard"
    ).strip()


    # --------------------------------------------------------
    # Validaciones
    # --------------------------------------------------------

    if not card_id:

        logger.warning(json.dumps({
            "correlation_id": correlation_id,
            "error": "cardId requerido"
        }))

        return connect_response(
            success=False,
            error="El campo cardId es requerido.",
            message="No pude identificar la tarjeta."
        )


    card_suffix = (
        card_id[-4:]
        if len(card_id) >= 4
        else "????"
    )


    logger.info(json.dumps({
        "correlation_id": correlation_id,
        "tool": "block_card",
        "action": action,
        "card_suffix": card_suffix
    }))


    if action != "blockCard":

        return connect_response(
            success=False,
            card_id=card_id,
            error=f"Acción no válida: {action}",
            message="La operación solicitada no es válida."
        )


    # --------------------------------------------------------
    # DynamoDB
    # --------------------------------------------------------

    table = dynamodb.Table(TABLE_NAME)


    try:

        response = table.query(
            IndexName="GSI1",
            KeyConditionExpression=Key("GSI1PK").eq(
                f"CARD#{card_id}"
            )
        )

        items = response.get("Items", [])

    except Exception as exc:

        logger.exception(json.dumps({
            "correlation_id": correlation_id,
            "tool": "block_card",
            "error": str(exc)
        }))

        return connect_response(
            success=False,
            card_id=card_id,
            error="DATABASE_ERROR",
            message="No fue posible consultar la tarjeta."
        )


    # --------------------------------------------------------
    # Tarjeta no encontrada
    # --------------------------------------------------------

    if not items:

        logger.warning(json.dumps({
            "correlation_id": correlation_id,
            "tool": "block_card",
            "card_suffix": card_suffix,
            "result": "not_found"
        }))

        return connect_response(
            success=False,
            card_id=card_id,
            error="CARD_NOT_FOUND",
            message="No se encontró la tarjeta indicada."
        )


    item = items[0]

    pk = item["PK"]
    sk = item["SK"]

    current_status = item.get(
        "status",
        ""
    )


    # --------------------------------------------------------
    # Validar estado
    # --------------------------------------------------------

    if current_status == "BLOCKED":

        return connect_response(
            success=True,
            card_id=card_id,
            previous_status="BLOCKED",
            new_status="BLOCKED",
            message=(
                f"La tarjeta terminada en {card_suffix} "
                "ya se encuentra bloqueada."
            )
        )


    if current_status not in BLOCKABLE_STATUSES:

        return connect_response(
            success=False,
            card_id=card_id,
            previous_status=current_status,
            new_status=current_status,
            error="INVALID_CARD_STATUS",
            message=(
                "La tarjeta no puede ser bloqueada. "
                f"Estado actual: {current_status}."
            )
        )


    # --------------------------------------------------------
    # Bloquear tarjeta
    # --------------------------------------------------------

    blocked_at = datetime.now(
        timezone.utc
    ).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )


    try:

        table.update_item(

            Key={
                "PK": pk,
                "SK": sk
            },

            UpdateExpression=(
                "SET #s = :new_status, "
                "blocked_at = :ts"
            ),

            ExpressionAttributeNames={
                "#s": "status"
            },

            ExpressionAttributeValues={
                ":new_status": "BLOCKED",
                ":ts": blocked_at,
                ":expected": current_status
            },

            ConditionExpression=(
                "#s = :expected"
            )
        )


    except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:

        logger.warning(json.dumps({
            "correlation_id": correlation_id,
            "tool": "block_card",
            "result": "conditional_check_failed"
        }))

        return connect_response(
            success=False,
            card_id=card_id,
            previous_status=current_status,
            error="CARD_STATUS_CHANGED",
            message=(
                "El estado de la tarjeta cambió durante "
                "la operación. Intenta nuevamente."
            )
        )


    except Exception as exc:

        logger.exception(json.dumps({
            "correlation_id": correlation_id,
            "tool": "block_card",
            "error": str(exc)
        }))

        return connect_response(
            success=False,
            card_id=card_id,
            previous_status=current_status,
            error="BLOCK_CARD_ERROR",
            message="No fue posible bloquear la tarjeta."
        )


    # --------------------------------------------------------
    # Mensaje por defecto
    # --------------------------------------------------------

    message = (
        f"La tarjeta terminada en {card_suffix} "
        "fue bloqueada correctamente. "
        "Ya no podrá utilizarse para nuevas transacciones. "
        "Puedes solicitar una tarjeta de reemplazo."
    )


    # --------------------------------------------------------
    # Bedrock
    # --------------------------------------------------------

    try:

        bedrock_message = invoke_bedrock(
            card_suffix,
            blocked_at
        )

        if bedrock_message:
            message = bedrock_message


    except Exception as exc:

        # IMPORTANTE:
        # Fallar Bedrock NO debe impedir el bloqueo.
        logger.warning(json.dumps({
            "correlation_id": correlation_id,
            "tool": "block_card",
            "bedrock_warning": str(exc)
        }))


    # --------------------------------------------------------
    # Log exitoso
    # --------------------------------------------------------

    logger.info(json.dumps({
        "correlation_id": correlation_id,
        "tool": "block_card",
        "result": "success",
        "card_suffix": card_suffix,
        "previous_status": current_status,
        "new_status": "BLOCKED"
    }))


    # --------------------------------------------------------
    # Respuesta para Amazon Connect STRING_MAP
    # --------------------------------------------------------

    return connect_response(
        success=True,
        card_id=card_id,
        previous_status=current_status,
        new_status="BLOCKED",
        blocked_at=blocked_at,
        message=message
    )
