"""
Lambda: get_order
Dominio: Retail
Descripción: Consulta el estado de un pedido por order_id desde DynamoDB
             y genera una respuesta conversacional usando Amazon Bedrock (Claude 3 Sonnet).
"""

import json
import logging
import os
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Key

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

dynamodb = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION_NAME", "us-east-1"))
bedrock  = boto3.client("bedrock-runtime", region_name=os.environ.get("AWS_REGION_NAME", "us-east-1"))

TABLE_NAME       = os.environ["DYNAMODB_TABLE_NAME"]
BEDROCK_MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "anthropic.claude-3-sonnet-20240229-v1:0")


def decimal_default(obj):
    """Serializar Decimal a float para JSON."""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Tipo no serializable: {type(obj)}")


def invoke_bedrock(order_data: dict) -> str:
    """
    Invoca Claude 3 Sonnet via bedrock-runtime para generar una respuesta
    conversacional con los datos del pedido.
    """
    prompt = (
        "Eres un asistente virtual de atención al cliente del dominio Retail. "
        "Responde siempre en español, de forma concisa y profesional.\n\n"
        f"Datos del pedido:\n{json.dumps(order_data, ensure_ascii=False, indent=2)}\n\n"
        "Genera un resumen claro del estado del pedido para el cliente, "
        "incluyendo estado actual, motivo de retraso si aplica, y fecha estimada de entrega."
    )

    body = json.dumps({
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 512,
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
        {"order_id": "ORD-1001"}

    Salida exitosa:
        {
            "order_id": "ORD-1001",
            "customer_name": "Laura Gómez",
            "status": "DELAYED",
            "original_delivery_date": "2026-10-03",
            "estimated_delivery_date": "2026-10-07",
            "delivery_address": "Av. Corrientes 1234, Buenos Aires",
            "delay_reason": "Carrier delay",
            "bedrock_response": "<respuesta generada por Claude>"
        }
    """
    correlation_id = context.aws_request_id

    logger.info(json.dumps({
        "correlation_id": correlation_id,
        "tool": "get_order",
        "event": event
    }))

    # --- Validar parámetros ---
    order_id = (event.get("order_id") or "").strip()
    if not order_id:
        logger.warning(json.dumps({
            "correlation_id": correlation_id,
            "tool": "get_order",
            "error": "order_id requerido"
        }))
        return {
            "statusCode": 400,
            "body": {"error": "El campo order_id es requerido."}
        }

    # --- Consultar DynamoDB ---
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
            "tool": "get_order",
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

    result = {
        "order_id":               item.get("order_id"),
        "customer_name":          item.get("customer_name"),
        "status":                 item.get("status"),
        "original_delivery_date": item.get("original_delivery_date"),
        "estimated_delivery_date":item.get("estimated_delivery_date"),
        "delivery_address":       item.get("delivery_address"),
        "delay_reason":           item.get("delay_reason"),
    }

    # --- Invocar Bedrock para generar respuesta conversacional ---
    try:
        result["bedrock_response"] = invoke_bedrock(result)
    except Exception as exc:
        logger.warning(json.dumps({
            "correlation_id": correlation_id,
            "tool": "get_order",
            "bedrock_warning": str(exc)
        }))
        result["bedrock_response"] = None

    logger.info(json.dumps({
        "correlation_id": correlation_id,
        "tool": "get_order",
        "result": "success",
        "order_id": order_id,
        "status": result["status"]
    }))

    return {"statusCode": 200, "body": result}
