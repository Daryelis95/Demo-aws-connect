"""
Lambda: get_transactions
Dominio: Banca
Descripción: Consulta los movimientos recientes de un cliente desde DynamoDB.
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
TABLE_NAME = os.environ["DYNAMODB_TABLE_NAME"]


def decimal_default(obj):
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Tipo no serializable: {type(obj)}")


def lambda_handler(event, context):
    """
    Entrada esperada:
        {"customer_id": "CUS-2001"}

    Salida exitosa:
        {
            "customer_id": "CUS-2001",
            "customer_name": "Martín Fernández",
            "transactions": [
                {
                    "txn_id": "TXN-9001",
                    "merchant": "Supermercado Norte",
                    "amount": 45.20,
                    "currency": "USD",
                    "date": "2026-10-04",
                    "status": "APPROVED",
                    "suspicious": false
                },
                {
                    "txn_id": "TXN-9002",
                    "merchant": "Electronics Store",
                    "amount": 850.00,
                    "currency": "USD",
                    "date": "2026-10-05",
                    "status": "APPROVED",
                    "suspicious": true
                }
            ]
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
        # Obtener perfil del cliente
        profile_response = table.get_item(
            Key={"PK": f"CUSTOMER#{customer_id}", "SK": "PROFILE"}
        )
        profile = profile_response.get("Item")

        if not profile:
            return {
                "statusCode": 404,
                "body": {"error": f"Cliente {customer_id} no encontrado."}
            }

        # Obtener transacciones: PK=CUSTOMER#<id> SK begins_with TXN#
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
            "txn_id": t.get("txn_id"),
            "merchant": t.get("merchant"),
            "amount": float(t.get("amount", 0)),
            "currency": t.get("currency", "USD"),
            "date": t.get("date"),
            "status": t.get("status"),
            "suspicious": t.get("suspicious", False),
        }
        for t in transactions
    ]

    result = {
        "customer_id": customer_id,
        "customer_name": profile.get("name"),
        "transactions": formatted_txns,
    }

    suspicious_count = sum(1 for t in formatted_txns if t["suspicious"])

    logger.info(json.dumps({
        "correlation_id": correlation_id,
        "tool": "get_transactions",
        "result": "success",
        "customer_id": customer_id,
        "transaction_count": len(formatted_txns),
        "suspicious_count": suspicious_count
    }))

    return {"statusCode": 200, "body": result}
