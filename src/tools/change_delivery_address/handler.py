"""
Lambda: change_delivery_address
Dominio: Retail
Descripción: Actualiza la dirección de entrega de un pedido en DynamoDB
             y genera una confirmación conversacional usando Amazon Bedrock (Claude 3 Sonnet).
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


def invoke_bedrock(order_id: str, previous_address: str, new_address: str) -> str:
    """
    Invoca Claude 3 Sonnet para generar un mensaje de confirmación del cambio
    de dirección de entrega.
    """
    prompt = (
        "Eres un asistente virtual de atención al cliente del dominio Retail. "
        "Responde siempre en español, de forma concisa y profesional.\n\n"
        f"Se actualizó exitosamente la dirección de entrega del pedido {order_id}:\n"
        f"- Dirección anterior: {previous_address}\n"
        f"- Nueva dirección: {new_address}\n\n"
        "Genera un mensaje de confirmación claro para el cliente, indicando que el "
        "cambio fue realizado y que el pedido será enviado a la nueva dirección."
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
        {"order_id": "ORD-1001", "new_address": "Av. Santa Fe 1800"}

    Salida exitosa:
        {
            "order_id": "ORD-1001",
            "previous_address": "Av. Corrientes 1234, Buenos Aires",
            "new_address": "Av. Santa Fe 1800",
            "updated_at": "2026-10-05T14:30:00Z",
            "bedrock_response": "<confirmación generada por Claude>"
        }
    """
    correlation_id = context.aws_request_id

    logger.info(json.dumps({
        "correlation_id": correlation_id,
        "tool": "change_delivery_address",
        "event": event
    }))

    order_id    = (event.get("order_id") or "").strip()
    new_address = (event.get("new_address") or "").strip()

    if not order_id or not new_address:
        logger.warning(json.dumps({
            "correlation_id": correlation_id,
            "tool": "change_delivery_address",
            "error": "order_id y new_address son requeridos"
        }))
        return {
            "statusCode": 400,
            "body": {"error": "Los campos order_id y new_address son requeridos."}
        }

    if len(new_address) > 500:
        return {
            "statusCode": 400,
            "body": {"error": "La dirección no puede superar los 500 caracteres."}
        }

    table = dynamodb.Table(TABLE_NAME)

    try:
        response = table.query(
            IndexName="GSI1",
            KeyConditionExpression=Key("GSI1PK").eq(f"ORDER#{order_id}")
        )
        items = response.get("Items", [])
    except Exception as exc:
        logger.error(json.dumps({
            "correlation_id": correlation_id,
            "tool": "change_delivery_address",
            "error": str(exc)
        }))
        return {
            "statusCode": 500,
            "body": {"error": "Error consultando la base de datos."}
        }

    if not items:
        return {
            "statusCode": 404,
            "body": {"error": f"Pedido {order_id} no encontrado."}
        }

    item             = items[0]
    pk               = item["PK"]
    sk               = item["SK"]
    previous_address = item.get("delivery_address", "")
    updated_at       = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    try:
        table.update_item(
            Key={"PK": pk, "SK": sk},
            UpdateExpression="SET delivery_address = :addr, updated_at = :ts",
            ExpressionAttributeValues={
                ":addr": new_address,
                ":ts":   updated_at,
            }
        )
    except Exception as exc:
        logger.error(json.dumps({
            "correlation_id": correlation_id,
            "tool": "change_delivery_address",
            "error": str(exc)
        }))
        return {
            "statusCode": 500,
            "body": {"error": "Error actualizando la dirección."}
        }

    result = {
        "order_id":         order_id,
        "previous_address": previous_address,
        "new_address":      new_address,
        "updated_at":       updated_at,
    }

    # --- Invocar Bedrock para generar confirmación conversacional ---
    try:
        result["bedrock_response"] = invoke_bedrock(order_id, previous_address, new_address)
    except Exception as exc:
        logger.warning(json.dumps({
            "correlation_id": correlation_id,
            "tool": "change_delivery_address",
            "bedrock_warning": str(exc)
        }))
        result["bedrock_response"] = None

    logger.info(json.dumps({
        "correlation_id": correlation_id,
        "tool": "change_delivery_address",
        "result": "success",
        "order_id": order_id
    }))

    return {"statusCode": 200, "body": result}
