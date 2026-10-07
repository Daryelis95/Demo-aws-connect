"""
Lambda: get_transactions
Dominio: Banca

Descripción:
Consulta los movimientos recientes de un cliente desde DynamoDB
y genera opcionalmente un análisis conversacional usando Amazon Bedrock.

Compatible con Amazon Connect:
{
  "Details": {
    "Parameters": {
      "action": "getTransactions",
      "customer_id": "ACC-1001"
    }
  }
}

Respuesta compatible con:
Amazon Connect -> ResponseValidation = STRING_MAP
"""

import json
import logging
import os
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Key


# ============================================================
# CONFIGURACIÓN
# ============================================================

logger = logging.getLogger()
logger.setLevel(os.getenv("LOG_LEVEL", "INFO"))

AWS_REGION = os.getenv("AWS_REGION_NAME", "us-east-1")

dynamodb = boto3.resource(
    "dynamodb",
    region_name=AWS_REGION
)

bedrock = boto3.client(
    "bedrock-runtime",
    region_name=AWS_REGION
)

TABLE_NAME = os.getenv("DYNAMODB_TABLE_NAME")

BEDROCK_MODEL_ID = os.getenv(
    "BEDROCK_MODEL_ID",
    "us.anthropic.claude-3-5-haiku-20241022-v1:0"
)


# ============================================================
# HELPERS
# ============================================================

def decimal_default(obj):
    if isinstance(obj, Decimal):
        return float(obj)

    raise TypeError(
        f"Tipo no serializable: {type(obj)}"
    )


def get_parameters(event):
    """
    Lee parámetros tanto desde Amazon Connect como
    desde una invocación directa de Lambda.
    """

    connect_parameters = (
        event
        .get("Details", {})
        .get("Parameters", {})
    )

    if connect_parameters:
        return connect_parameters

    return event


def invoke_bedrock(customer_name, transactions):
    """
    Genera un resumen conversacional de los movimientos.
    """

    suspicious_transactions = [
        transaction
        for transaction in transactions
        if transaction.get("suspicious")
    ]

    prompt = (
        "Eres un asistente virtual de atención al cliente del dominio Banca. "
        "Responde siempre en español, de forma concisa y profesional. "
        "Nunca menciones números completos de tarjetas.\n\n"
        f"Cliente: {customer_name}\n"
        f"Movimientos recientes:\n"
        f"{json.dumps(transactions, ensure_ascii=False, indent=2)}\n\n"
    )

    if suspicious_transactions:
        prompt += (
            f"Se detectaron {len(suspicious_transactions)} "
            "transacción(es) sospechosa(s). "
            "Presenta los movimientos al cliente, destaca las transacciones "
            "sospechosas y pregunta si las reconoce. "
            "No tomes ninguna acción sin confirmación explícita."
        )
    else:
        prompt += (
            "Presenta un resumen claro de los movimientos recientes. "
            "No se detectaron transacciones sospechosas."
        )

    body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 768,
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
# HANDLER
# ============================================================

def lambda_handler(event, context):

    correlation_id = context.aws_request_id

    logger.info(
        json.dumps(
            {
                "correlation_id": correlation_id,
                "tool": "get_transactions",
                "event": event
            },
            default=decimal_default
        )
    )

    # --------------------------------------------------------
    # 1. Leer parámetros
    # --------------------------------------------------------

    parameters = get_parameters(event)

    action = str(
        parameters.get(
            "action",
            "getTransactions"
        )
    ).strip()

    customer_id = str(
        parameters.get(
            "customer_id",
            ""
        )
    ).strip()

    logger.info(
        json.dumps(
            {
                "correlation_id": correlation_id,
                "action": action,
                "customer_id": customer_id
            }
        )
    )

    # --------------------------------------------------------
    # 2. Validaciones
    # --------------------------------------------------------

    if not customer_id:

        logger.warning(
            json.dumps(
                {
                    "correlation_id": correlation_id,
                    "error": "customer_id requerido"
                }
            )
        )

        return {
            "success": "false",
            "error": "El campo customer_id es requerido."
        }

    if not TABLE_NAME:

        logger.error(
            "La variable DYNAMODB_TABLE_NAME no está configurada."
        )

        return {
            "success": "false",
            "error": "DYNAMODB_TABLE_NAME no está configurada."
        }

    # --------------------------------------------------------
    # 3. Consultar DynamoDB
    # --------------------------------------------------------

    table = dynamodb.Table(
        TABLE_NAME
    )

    try:

        # Buscar perfil del cliente
        profile_response = table.get_item(
            Key={
                "PK": f"CUSTOMER#{customer_id}",
                "SK": "PROFILE"
            }
        )

        profile = profile_response.get(
            "Item",
            {}
        )

        # Buscar transacciones
        transaction_response = table.query(
            KeyConditionExpression=(
                Key("PK").eq(
                    f"CUSTOMER#{customer_id}"
                )
                &
                Key("SK").begins_with(
                    "TXN#"
                )
            )
        )

        transactions = transaction_response.get(
            "Items",
            []
        )

        if not profile and not transactions:

            logger.warning(
                json.dumps(
                    {
                        "correlation_id": correlation_id,
                        "customer_id": customer_id,
                        "error": "Cliente no encontrado"
                    }
                )
            )

            return {
                "success": "false",
                "customerId": customer_id,
                "error": f"Cliente {customer_id} no encontrado."
            }

    except Exception as exc:

        logger.exception(
            "Error consultando DynamoDB"
        )

        return {
            "success": "false",
            "customerId": customer_id,
            "error": f"Error consultando DynamoDB: {str(exc)}"
        }

    # --------------------------------------------------------
    # 4. Normalizar movimientos
    # --------------------------------------------------------

    formatted_transactions = []

    for transaction in transactions:

        suspicious_value = transaction.get(
            "suspicious",
            False
        )

        is_suspicious = (
            suspicious_value is True
            or str(
                suspicious_value
            ).lower() == "true"
        )

        # Extraer card_id buscando tanto 'card_id' como 'cardId'
        txn_card_id = str(
            transaction.get(
                "card_id",
                transaction.get("cardId", "")
            )
        )

        formatted_transactions.append(
            {
                "txn_id": str(
                    transaction.get(
                        "txn_id",
                        ""
                    )
                ),

                "card_id": txn_card_id,

                "merchant": str(
                    transaction.get(
                        "merchant",
                        ""
                    )
                ),

                "amount": float(
                    transaction.get(
                        "amount",
                        0
                    )
                ),

                "currency": str(
                    transaction.get(
                        "currency",
                        "USD"
                    )
                ),

                "date": str(
                    transaction.get(
                        "date",
                        ""
                    )
                ),

                "status": str(
                    transaction.get(
                        "status",
                        ""
                    )
                ),

                "suspicious": is_suspicious
            }
        )

    # --------------------------------------------------------
    # 5. Obtener movimiento sospechoso
    # --------------------------------------------------------

    suspicious_transactions = [
        transaction
        for transaction in formatted_transactions
        if transaction["suspicious"]
    ]

    suspicious_transaction = (
        suspicious_transactions[0]
        if suspicious_transactions
        else (formatted_transactions[0] if formatted_transactions else None)
    )

    suspicious_count = len(
        suspicious_transactions
    )

    # --------------------------------------------------------
    # 6. Datos del cliente (con fallback a la transacción)
    # --------------------------------------------------------

    customer_name = str(
        profile.get(
            "name",
            customer_id
        )
    )

    account_id = str(
        profile.get(
            "account_id",
            profile.get(
                "accountId",
                customer_id
            )
        )
    )

    # Buscar card_id en PROFILE primero; si no existe, buscarlo en la transacción
    card_id = str(
        profile.get(
            "card_id",
            profile.get(
                "cardId",
                ""
            )
        )
    )

    if not card_id and suspicious_transaction:
        card_id = str(suspicious_transaction.get("card_id", ""))

    card_last4 = str(
        profile.get(
            "card_last4",
            profile.get(
                "cardLast4",
                ""
            )
        )
    )

    if not card_last4 and card_id and len(card_id) >= 4:
        card_last4 = card_id[-4:]

    card_status = str(
        profile.get(
            "card_status",
            profile.get(
                "cardStatus",
                "ACTIVE"
            )
        )
    )

    # --------------------------------------------------------
    # 7. Datos de operación sospechosa
    # --------------------------------------------------------

    if suspicious_transaction:

        transaction_id = str(
            suspicious_transaction.get(
                "txn_id",
                ""
            )
        )

        merchant = str(
            suspicious_transaction.get(
                "merchant",
                ""
            )
        )

        amount = str(
            suspicious_transaction.get(
                "amount",
                ""
            )
        )

        currency = str(
            suspicious_transaction.get(
                "currency",
                "USD"
            )
        )

        transaction_date = str(
            suspicious_transaction.get(
                "date",
                ""
            )
        )

        suspicious = "true" if suspicious_count > 0 else "false"

    else:

        transaction_id = ""
        merchant = ""
        amount = ""
        currency = ""
        transaction_date = ""
        suspicious = "false"

    # --------------------------------------------------------
    # 8. Invocar Bedrock
    # --------------------------------------------------------

    bedrock_response = ""

    try:

        bedrock_response = invoke_bedrock(
            customer_name,
            formatted_transactions
        )

    except Exception as exc:

        logger.warning(
            json.dumps(
                {
                    "correlation_id": correlation_id,
                    "bedrock_warning": str(exc)
                }
            )
        )

        # Bedrock no debe impedir que el flujo continúe
        bedrock_response = (
            "No fue posible generar el resumen automático."
        )

    # --------------------------------------------------------
    # 9. Respuesta compatible con STRING_MAP
    # --------------------------------------------------------

    result = {

        "success": "true",

        "customerId": customer_id,
        "customerName": customer_name,

        "accountId": account_id,

        "cardId": card_id,
        "cardLast4": card_last4,
        "cardStatus": card_status,

        "transactionId": transaction_id,

        "merchant": merchant,
        "amount": amount,
        "currency": currency,
        "transactionDate": transaction_date,

        "suspicious": suspicious,

        "suspiciousCount": str(
            suspicious_count
        ),

        "transactionCount": str(
            len(
                formatted_transactions
            )
        ),

        "bedrockResponse": str(
            bedrock_response or ""
        )
    }

    logger.info(
        json.dumps(
            {
                "correlation_id": correlation_id,
                "tool": "get_transactions",
                "result": result
            },
            ensure_ascii=False
        )
    )

    return result
