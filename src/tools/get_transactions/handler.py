"""
Lambda: get_transactions
Dominio: Banca — V3

Descripción:
Consulta el perfil, tarjeta y movimientos recientes de un cliente desde DynamoDB.
Devuelve el movimiento sospechoso activo y los metadatos necesarios para el flujo V3.

Compatible con Amazon Connect:
{
  "Details": {
    "Parameters": {
      "action":      "getTransactions",
      "customer_id": "CUS-2001"
    }
  }
}

Respuesta STRING_MAP (todos los valores son strings):
{
  "success":        "true",
  "customerId":     "CUS-2001",
  "customerName":   "Martín Fernández",
  "accountId":      "CUS-2001",
  "cardId":         "CARD-4455",
  "cardLast4":      "4455",
  "cardReference":  "****4455",
  "cardStatus":     "ACTIVE",
  "transactionId":  "TXN-9002",
  "operationId":    "FRAUD-CUS-2001-TXN-9002",
  "merchant":       "Electronics Store",
  "amount":         "850.0",
  "currency":       "USD",
  "transactionDate":"2026-10-05",
  "suspicious":     "true",
  "suspiciousCount":"1",
  "transactionCount":"2",
  "bedrockResponse":""
}
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

dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
bedrock  = boto3.client("bedrock-runtime", region_name=AWS_REGION)

TABLE_NAME       = os.getenv("DYNAMODB_TABLE_NAME")
BEDROCK_MODEL_ID = os.getenv("BEDROCK_MODEL_ID", "us.anthropic.claude-3-5-haiku-20241022-v1:0")
ENABLE_BEDROCK   = os.getenv("ENABLE_BEDROCK_SUMMARY", "false").lower() == "true"
BEDROCK_MAX_CHARS = 500


# ============================================================
# HELPERS
# ============================================================

def decimal_default(obj):
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Tipo no serializable: {type(obj)}")


def get_parameters(event):
    """Lee parámetros desde Connect o desde invocación directa."""
    connect_params = event.get("Details", {}).get("Parameters", {})
    return connect_params if connect_params else event


def mask_card(card_id):
    """Devuelve (cardReference, cardLast4): ('****4455', '4455')"""
    suffix = card_id[-4:] if len(card_id) >= 4 else "????"
    return f"****{suffix}", suffix


def invoke_bedrock(customer_name, transactions):
    """
    Genera un resumen conversacional breve de los movimientos.
    Solo se invoca si ENABLE_BEDROCK_SUMMARY=true.
    Nunca expone números completos de tarjetas.
    """
    suspicious = [t for t in transactions if t.get("suspicious")]

    prompt = (
        "Eres un asistente de atención al cliente bancario. "
        "Responde en español, de forma concisa y profesional. "
        "Nunca menciones números completos de tarjetas.\n\n"
        f"Cliente: {customer_name}\n"
        f"Movimientos: {json.dumps(transactions, ensure_ascii=False)}\n\n"
    )

    if suspicious:
        prompt += (
            f"Hay {len(suspicious)} transacción(es) sospechosa(s). "
            "Menciona brevemente el cargo más reciente sospechoso."
        )
    else:
        prompt += "Resume brevemente los movimientos recientes."

    body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 200,
        "messages": [{"role": "user", "content": prompt}]
    }

    response      = bedrock.invoke_model(
        modelId=BEDROCK_MODEL_ID,
        contentType="application/json",
        accept="application/json",
        body=json.dumps(body)
    )
    response_body = json.loads(response["body"].read())
    text          = response_body["content"][0]["text"].strip()

    # Limitar a BEDROCK_MAX_CHARS para no saturar atributos de Connect
    return text[:BEDROCK_MAX_CHARS] if len(text) > BEDROCK_MAX_CHARS else text


# ============================================================
# HANDLER
# ============================================================

def lambda_handler(event, context):

    correlation_id = context.aws_request_id

    # Log de entrada sin PII — sin loguear el event completo
    logger.info(json.dumps({
        "event":          "get_transactions_invoked",
        "correlation_id": correlation_id,
        "source":         "amazon_connect" if "Details" in event else "direct"
    }))

    # --------------------------------------------------------
    # 1. Leer parámetros
    # --------------------------------------------------------

    parameters  = get_parameters(event)
    action      = str(parameters.get("action", "getTransactions")).strip()
    customer_id = str(parameters.get("customer_id", "")).strip()

    # Normalizar customer_id: si el usuario ingresó solo el número
    # (ej: "2001") agregar el prefijo "CUS-" → "CUS-2001"
    if customer_id and not customer_id.upper().startswith("CUS-"):
        customer_id = f"CUS-{customer_id}"

    logger.info(json.dumps({
        "event":          "get_transactions_params",
        "correlation_id": correlation_id,
        "action":         action,
        "customer_id":    customer_id
    }))

    # --------------------------------------------------------
    # 2. Validaciones
    # --------------------------------------------------------

    if not customer_id:
        logger.warning(json.dumps({
            "event":          "get_transactions_validation_error",
            "correlation_id": correlation_id,
            "error_code":     "MISSING_CUSTOMER_ID"
        }))
        return {"success": "false", "errorCode": "MISSING_CUSTOMER_ID"}

    if not TABLE_NAME:
        logger.error("DYNAMODB_TABLE_NAME no está configurada.")
        return {"success": "false", "errorCode": "MISSING_ENV_VAR"}

    # --------------------------------------------------------
    # 3. Consultar DynamoDB
    # --------------------------------------------------------

    table = dynamodb.Table(TABLE_NAME)

    try:
        # Perfil del cliente
        profile_resp = table.get_item(
            Key={"PK": f"CUSTOMER#{customer_id}", "SK": "PROFILE"}
        )
        profile = profile_resp.get("Item", {})

        # Tarjeta — leer cardStatus directamente del ítem CARD#
        # (no confiar en el PROFILE que puede estar desactualizado)
        card_items_resp = table.query(
            KeyConditionExpression=(
                Key("PK").eq(f"CUSTOMER#{customer_id}") &
                Key("SK").begins_with("CARD#")
            )
        )
        card_items = card_items_resp.get("Items", [])

        # Transacciones
        txn_resp = table.query(
            KeyConditionExpression=(
                Key("PK").eq(f"CUSTOMER#{customer_id}") &
                Key("SK").begins_with("TXN#")
            )
        )
        transactions_raw = txn_resp.get("Items", [])

    except Exception:
        logger.error(json.dumps({
            "event":          "get_transactions_db_error",
            "correlation_id": correlation_id,
            "error_code":     "DATABASE_ERROR"
        }))
        return {
            "success":     "false",
            "customerId":  customer_id,
            "errorCode":   "DATABASE_ERROR"
        }

    if not profile and not transactions_raw:
        logger.warning(json.dumps({
            "event":          "get_transactions_not_found",
            "correlation_id": correlation_id,
            "customer_id":    customer_id
        }))
        return {
            "success":    "false",
            "customerId": customer_id,
            "errorCode":  "CUSTOMER_NOT_FOUND"
        }

    # --------------------------------------------------------
    # 4. Datos de la tarjeta (desde ítem CARD#, no del PROFILE)
    # --------------------------------------------------------

    card_item   = card_items[0] if card_items else {}
    card_id     = str(card_item.get("card_id", card_item.get("cardId", "")))
    card_status = str(card_item.get("status", "UNKNOWN"))

    card_reference, card_last4 = mask_card(card_id) if card_id else ("", "")

    # --------------------------------------------------------
    # 5. Datos del cliente
    # --------------------------------------------------------

    customer_name = str(profile.get("name", customer_id))
    account_id    = str(profile.get("account_id", profile.get("accountId", customer_id)))

    # --------------------------------------------------------
    # 6. Normalizar transacciones
    # --------------------------------------------------------

    formatted_transactions = []

    for txn in transactions_raw:
        suspicious_val = txn.get("suspicious", False)
        is_suspicious  = (
            suspicious_val is True
            or str(suspicious_val).lower() == "true"
        )
        formatted_transactions.append({
            "txn_id":    str(txn.get("txn_id", "")),
            "card_id":   str(txn.get("card_id", txn.get("cardId", ""))),
            "merchant":  str(txn.get("merchant", "")),
            "amount":    float(txn.get("amount", 0)),
            "currency":  str(txn.get("currency", "USD")),
            "date":      str(txn.get("date", "")),
            "status":    str(txn.get("status", "")),
            "suspicious": is_suspicious
        })

    # --------------------------------------------------------
    # 7. Seleccionar transacción sospechosa principal
    # --------------------------------------------------------

    suspicious_list  = [t for t in formatted_transactions if t["suspicious"]]
    suspicious_count = len(suspicious_list)
    suspicious_txn   = suspicious_list[0] if suspicious_list else (
        formatted_transactions[0] if formatted_transactions else None
    )

    if suspicious_txn:
        transaction_id   = str(suspicious_txn.get("txn_id", ""))
        merchant         = str(suspicious_txn.get("merchant", ""))
        amount           = str(suspicious_txn.get("amount", ""))
        currency         = str(suspicious_txn.get("currency", "USD"))
        transaction_date = str(suspicious_txn.get("date", ""))
        suspicious_flag  = "true" if suspicious_count > 0 else "false"
        # operationId — identificador único de la operación de fraude
        operation_id     = f"FRAUD-{customer_id}-{transaction_id}" if transaction_id else ""
    else:
        transaction_id   = ""
        merchant         = ""
        amount           = ""
        currency         = ""
        transaction_date = ""
        suspicious_flag  = "false"
        operation_id     = ""

    # --------------------------------------------------------
    # 8. Bedrock (opcional — solo si ENABLE_BEDROCK_SUMMARY=true)
    # --------------------------------------------------------

    bedrock_response = ""

    if ENABLE_BEDROCK:
        try:
            bedrock_response = invoke_bedrock(customer_name, formatted_transactions)
        except Exception:
            logger.warning(json.dumps({
                "event":          "get_transactions_bedrock_warning",
                "correlation_id": correlation_id
            }))
            bedrock_response = ""

    # --------------------------------------------------------
    # 9. Log de salida (sin PII sensible)
    # --------------------------------------------------------

    logger.info(json.dumps({
        "event":           "get_transactions_success",
        "correlation_id":  correlation_id,
        "customer_id":     customer_id,
        "card_suffix":     card_last4,
        "card_status":     card_status,
        "suspicious_count": suspicious_count,
        "transaction_count": len(formatted_transactions),
        "operation_id":    operation_id
    }))

    # --------------------------------------------------------
    # 10. Respuesta STRING_MAP para Amazon Connect
    # --------------------------------------------------------

    return {
        "success":          "true",
        "customerId":       customer_id,
        "customerName":     customer_name,
        "accountId":        account_id,
        "cardId":           card_id,
        "cardLast4":        card_last4,
        "cardReference":    card_reference,
        "cardStatus":       card_status,
        "transactionId":    transaction_id,
        "operationId":      operation_id,
        "merchant":         merchant,
        "amount":           amount,
        "currency":         currency,
        "transactionDate":  transaction_date,
        "suspicious":       suspicious_flag,
        "suspiciousCount":  str(suspicious_count),
        "transactionCount": str(len(formatted_transactions)),
        "bedrockResponse":  bedrock_response
    }
