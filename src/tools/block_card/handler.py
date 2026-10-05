"""
Lambda: block_card
Dominio: Banca
Descripción: Bloquea una tarjeta bancaria (ACTIVE → BLOCKED) en DynamoDB.
"""

import json
import logging
import os
from datetime import datetime, timezone

import boto3
from boto3.dynamodb.conditions import Key

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

dynamodb = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION_NAME", "us-east-1"))
TABLE_NAME = os.environ["DYNAMODB_TABLE_NAME"]

# Estados de tarjeta permitidos
VALID_STATUSES = {"ACTIVE", "BLOCKED", "EXPIRED"}
BLOCKABLE_STATUSES = {"ACTIVE"}


def lambda_handler(event, context):
    """
    Entrada esperada:
        {"card_id": "CARD-4455"}

    Salida exitosa:
        {
            "card_id": "CARD-4455",
            "previous_status": "ACTIVE",
            "new_status": "BLOCKED",
            "blocked_at": "2026-10-05T14:30:00Z"
        }

    SEGURIDAD: Solo registra los últimos 4 dígitos de la tarjeta en logs.
    """
    correlation_id = context.aws_request_id
    card_id = (event.get("card_id") or "").strip()

    # Log sin exponer el card_id completo
    card_suffix = card_id[-4:] if len(card_id) >= 4 else "????"
    logger.info(json.dumps({
        "correlation_id": correlation_id,
        "tool": "block_card",
        "card_suffix": card_suffix
    }))

    if not card_id:
        return {
            "statusCode": 400,
            "body": {"error": "El campo card_id es requerido."}
        }

    table = dynamodb.Table(TABLE_NAME)

    try:
        # Buscar la tarjeta por GSI1: GSI1PK=CARD#<card_id>
        response = table.query(
            IndexName="GSI1",
            KeyConditionExpression=Key("GSI1PK").eq(f"CARD#{card_id}")
        )
        items = response.get("Items", [])
    except Exception as exc:
        logger.error(json.dumps({
            "correlation_id": correlation_id,
            "tool": "block_card",
            "error": str(exc)
        }))
        return {
            "statusCode": 500,
            "body": {"error": "Error consultando la base de datos."}
        }

    if not items:
        return {
            "statusCode": 404,
            "body": {"error": f"Tarjeta no encontrada."}
        }

    item = items[0]
    pk = item["PK"]
    sk = item["SK"]
    current_status = item.get("status", "")

    # Verificar que la tarjeta puede ser bloqueada
    if current_status not in BLOCKABLE_STATUSES:
        return {
            "statusCode": 409,
            "body": {
                "error": f"La tarjeta no puede ser bloqueada. Estado actual: {current_status}."
            }
        }

    blocked_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    try:
        table.update_item(
            Key={"PK": pk, "SK": sk},
            UpdateExpression="SET #s = :new_status, blocked_at = :ts",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={
                ":new_status": "BLOCKED",
                ":ts": blocked_at,
                ":expected": current_status,
            },
            # Condición optimista: el estado no cambió entre la lectura y la escritura
            ConditionExpression="#s = :expected"
        )
    except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
        return {
            "statusCode": 409,
            "body": {"error": "El estado de la tarjeta cambió durante la operación. Intenta nuevamente."}
        }
    except Exception as exc:
        logger.error(json.dumps({
            "correlation_id": correlation_id,
            "tool": "block_card",
            "error": str(exc)
        }))
        return {
            "statusCode": 500,
            "body": {"error": "Error al bloquear la tarjeta."}
        }

    result = {
        "card_id": card_id,
        "previous_status": current_status,
        "new_status": "BLOCKED",
        "blocked_at": blocked_at,
    }

    logger.info(json.dumps({
        "correlation_id": correlation_id,
        "tool": "block_card",
        "result": "success",
        "card_suffix": card_suffix,
        "previous_status": current_status,
        "new_status": "BLOCKED"
    }))

    return {"statusCode": 200, "body": result}
