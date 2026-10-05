"""
Lambda: change_delivery_address
Dominio: Retail
Descripción: Actualiza la dirección de entrega de un pedido en DynamoDB.
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


def lambda_handler(event, context):
    """
    Entrada esperada:
        {"order_id": "ORD-1001", "new_address": "Av. Santa Fe 1800"}

    Salida exitosa:
        {
            "order_id": "ORD-1001",
            "previous_address": "Av. Corrientes 1234, Buenos Aires",
            "new_address": "Av. Santa Fe 1800",
            "updated_at": "2026-10-05T14:30:00Z"
        }
    """
    correlation_id = context.aws_request_id

    logger.info(json.dumps({
        "correlation_id": correlation_id,
        "tool": "change_delivery_address",
        "event": event
    }))

    order_id = (event.get("order_id") or "").strip()
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
        # Buscar el ítem por GSI1
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

    item = items[0]
    pk = item["PK"]
    sk = item["SK"]
    previous_address = item.get("delivery_address", "")
    updated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    try:
        table.update_item(
            Key={"PK": pk, "SK": sk},
            UpdateExpression="SET delivery_address = :addr, updated_at = :ts",
            ExpressionAttributeValues={
                ":addr": new_address,
                ":ts": updated_at,
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
        "order_id": order_id,
        "previous_address": previous_address,
        "new_address": new_address,
        "updated_at": updated_at,
    }

    logger.info(json.dumps({
        "correlation_id": correlation_id,
        "tool": "change_delivery_address",
        "result": "success",
        "order_id": order_id
    }))

    return {"statusCode": 200, "body": result}
