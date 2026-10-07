"""
Lambda: get_transactions
Dominio: Banca
Descripción: Consulta los movimientos recientes de un cliente desde DynamoDB
             y genera un análisis conversacional usando Amazon Bedrock (Claude 3 Sonnet).
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
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Tipo no serializable: {type(obj)}")


def invoke_bedrock(customer_name: str, transactions: list) -> str:
    """
    Invoca Claude 3 Sonnet para generar un resumen de los movimientos bancarios,
    destacando transacciones sospechosas si las hay.
    """
    suspicious = [t for t in transactions if t.get("suspicious")]

    prompt = (
        "Eres un asistente virtual de atención al cliente del dominio Banca. "
        "Responde siempre en español, de forma concisa y profesional. "
        "Nunca menciones números completos de tarjetas.\n\n"
        f"Cliente: {customer_name}\n"
        f"Movimientos recientes:\n{json.dumps(transactions, ensure_ascii=False, indent=2)}\n\n"
    )

    if suspicious:
        prompt += (
            f"Se detectaron {len(suspicious)} transacción(es) sospechosa(s). "
            "Presenta los movimientos al cliente, destaca las transacciones sospechosas "
            "y pregunta si las reconoce. No tomes ninguna acción sin confirmación explícita."
        )
    else:
        prompt += (
            "Presenta un resumen claro de los movimientos recientes al cliente. "
            "No se detectaron transacciones sospechosas."
        )

    body = json.dumps({
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 768,
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
        {"customer_id": "CUS-2001"}

    Salida exitosa:
        {
            "customer_id": "CUS-2001",
            "customer_name": "Martín Fernández",
            "transactions": [...],
            "bedrock_response": "<análisis generado por Claude>"
        }
    """
    correlation_id = context.aws_request_id

    logger.info(json.dumps({
        "correlation_id": correlation_id,
        "tool": "get_transactions",
        "event": event
    }))

    customer_id = (event.get("customer_id") or "").strip()
    if not customer_id:
        logger.warning(json.dumps({
            "correlation_id": correlation_id,
            "tool": "get_transactions",
            "error": "customer_id requerido"
        }))
        return {
            "statusCode": 400,
            "body": {"error": "El campo customer_id es requerido."}
        }

    table = dynamodb.Table(TABLE_NAME)

    try:
        profile_response = table.get_item(
            Key={"PK": f"CUSTOMER#{customer_id}", "SK": "PROFILE"}
        )
        profile = profile_response.get("Item")

        if not profile:
            return {
                "statusCode": 404,
                "body": {"error": f"Cliente {customer_id} no encontrado."}
            }

        txn_response = table.query(
            KeyConditionExpression=(
                Key("PK").eq(f"CUSTOMER#{customer_id}") &
                Key("SK").begins_with("TXN#")
            )
        )
        transactions = txn_response.get("Items", [])

    except Exception as exc:
        logger.error(json.dumps({
            "correlation_id": correlation_id,
            "tool": "get_transactions",
            "error": str(exc)
        }))
        return {
            "statusCode": 500,
            "body": {"error": "Error consultando la base de datos."}
        }

    formatted_txns = [
        {
            "txn_id":    t.get("txn_id"),
            "merchant":  t.get("merchant"),
            "amount":    float(t.get("amount", 0)),
            "currency":  t.get("currency", "USD"),
            "date":      t.get("date"),
            "status":    t.get("status"),
            "suspicious":t.get("suspicious", False),
        }
        for t in transactions
    ]

    customer_name   = profile.get("name", customer_id)
    suspicious_count = sum(1 for t in formatted_txns if t["suspicious"])

    result = {
        "customer_id":   customer_id,
        "customer_name": customer_name,
        "transactions":  formatted_txns,
    }

    # --- Invocar Bedrock para generar análisis conversacional ---
    try:
        result["bedrock_response"] = invoke_bedrock(customer_name, formatted_txns)
    except Exception as exc:
        logger.warning(json.dumps({
            "correlation_id": correlation_id,
            "tool": "get_transactions",
            "bedrock_warning": str(exc)
        }))
        result["bedrock_response"] = None

    logger.info(json.dumps({
        "correlation_id": correlation_id,
        "tool": "get_transactions",
        "result": "success",
        "customer_id": customer_id,
        "transaction_count": len(formatted_txns),
        "suspicious_count": suspicious_count
    }))

    return {"statusCode": 200, "body": result}
