"""
Lambda: block_card
Dominio: Banca
Descripción: Bloquea una tarjeta bancaria (ACTIVE → BLOCKED) en DynamoDB
             y genera un mensaje de confirmación usando Amazon Bedrock (Claude 3 Sonnet).
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
bedrock  = boto3.client("bedrock-runtime", region_name=os.environ.get("AWS_REGION_NAME", "us-east-1"))

TABLE_NAME       = os.environ["DYNAMODB_TABLE_NAME"]
BEDROCK_MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "anthropic.claude-3-sonnet-20240229-v1:0")

BLOCKABLE_STATUSES = {"ACTIVE"}


def invoke_bedrock(card_suffix: str, blocked_at: str) -> str:
    """
    Invoca Claude 3 Sonnet para generar un mensaje de confirmación del bloqueo
    de la tarjeta. Nunca expone el número completo de la tarjeta.
    """
    prompt = (
        "Eres un asistente virtual de atención al cliente del dominio Banca. "
        "Responde siempre en español, de forma concisa y profesional. "
        "Nunca menciones números completos de tarjetas.\n\n"
        f"Se bloqueó exitosamente la tarjeta terminada en {card_suffix} "
        f"el {blocked_at}.\n\n"
        "Genera un mensaje de confirmación claro para el cliente indicando que la "
        "tarjeta fue bloqueada, que ya no podrá ser utilizada para nuevas transacciones, "
        "y que puede contactar al banco para solicitar una tarjeta de reemplazo."
    )

    body = json.dumps({
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 256,
        "messages": [
            {"role": "user", "content": prompt}
        ]
    })

    response = bedrock.invoke_model(
        modelId=BEDROCK_MODEL_ID,
        contentType="application/json",
        accept="application/json",
        body=body,
    )

    response_body = json.loads(response["body"].read())
    return response_body["content"][0]["text"].strip()


def lambda_handler(event, context):
    """
    Entrada esperada:
        {"card_id": "CARD-4455"}

    Salida exitosa:
        {
            "card_id": "CARD-4455",
            "previous_status": "ACTIVE",
            "new_status": "BLOCKED",
            "blocked_at": "2026-10-05T14:30:00Z",
            "bedrock_response": "<confirmación generada por Claude>"
        }

    SEGURIDAD: Solo registra los últimos 4 dígitos de la tarjeta en logs.
    """
    correlation_id = context.aws_request_id
    card_id        = (event.get("card_id") or "").strip()

    # Solo los últimos 4 dígitos en logs
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
            "body": {"error": "Tarjeta no encontrada."}
        }

    item           = items[0]
    pk             = item["PK"]
    sk             = item["SK"]
    current_status = item.get("status", "")

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
                ":ts":         blocked_at,
                ":expected":   current_status,
            },
            # Escritura optimista: el estado no cambió entre la lectura y la escritura
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
        "card_id":         card_id,
        "previous_status": current_status,
        "new_status":      "BLOCKED",
        "blocked_at":      blocked_at,
    }

    # --- Invocar Bedrock para generar confirmación conversacional ---
    try:
        result["bedrock_response"] = invoke_bedrock(card_suffix, blocked_at)
    except Exception as exc:
        logger.warning(json.dumps({
            "correlation_id": correlation_id,
            "tool": "block_card",
            "bedrock_warning": str(exc)
        }))
        result["bedrock_response"] = None

    logger.info(json.dumps({
        "correlation_id": correlation_id,
        "tool": "block_card",
        "result": "success",
        "card_suffix": card_suffix,
        "previous_status": current_status,
        "new_status": "BLOCKED"
    }))

    return {"statusCode": 200, "body": result}
