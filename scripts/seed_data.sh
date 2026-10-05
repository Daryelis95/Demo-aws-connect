#!/usr/bin/env bash
# =============================================================================
# seed_data.sh — Carga datos ficticios en DynamoDB para la demo
#
# Uso:
#   bash scripts/seed_data.sh [sandbox]
#
# Los datos cargados representan:
#   Retail:  cliente Laura Gómez con pedido ORD-1001 en estado DELAYED
#   Banca:   cliente Martín Fernández con tarjeta CARD-4455 y 2 transacciones
# =============================================================================

set -euo pipefail

ENVIRONMENT="${1:-sandbox}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_ENV_DIR="${ROOT_DIR}/infra/environments/${ENVIRONMENT}"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Obtener el nombre de la tabla desde los outputs de Terraform
get_table_name() {
  cd "${INFRA_ENV_DIR}"
  terraform output -raw dynamodb_table_name 2>/dev/null || {
    log_error "No se pudo obtener el nombre de la tabla desde terraform output."
    log_error "Asegúrate de haber ejecutado terraform apply primero."
    exit 1
  }
}

# -----------------------------------------------------------------------------
# Datos Retail — cliente CUS-1001, pedido ORD-1001
# -----------------------------------------------------------------------------
seed_retail() {
  local table="$1"

  log_info "Cargando datos Retail..."

  # Perfil del cliente Retail
  aws dynamodb put-item \
    --table-name "${table}" \
    --item '{
      "PK":          {"S": "CUSTOMER#CUS-1001"},
      "SK":          {"S": "PROFILE"},
      "customer_id": {"S": "CUS-1001"},
      "name":        {"S": "Laura Gómez"},
      "email":       {"S": "laura.gomez@example.com"},
      "domain":      {"S": "RETAIL"},
      "created_at":  {"S": "2026-01-15T10:00:00Z"}
    }'

  # Pedido ORD-1001 (status: DELAYED)
  aws dynamodb put-item \
    --table-name "${table}" \
    --item '{
      "PK":                     {"S": "CUSTOMER#CUS-1001"},
      "SK":                     {"S": "ORDER#ORD-1001"},
      "GSI1PK":                 {"S": "ORDER#ORD-1001"},
      "GSI1SK":                 {"S": "CUSTOMER#CUS-1001"},
      "order_id":               {"S": "ORD-1001"},
      "customer_id":            {"S": "CUS-1001"},
      "customer_name":          {"S": "Laura Gómez"},
      "status":                 {"S": "DELAYED"},
      "original_delivery_date": {"S": "2026-10-03"},
      "estimated_delivery_date":{"S": "2026-10-07"},
      "delivery_address":       {"S": "Av. Corrientes 1234, Buenos Aires"},
      "delay_reason":           {"S": "Carrier delay"},
      "items":                  {"S": "Auriculares Bluetooth x1"},
      "created_at":             {"S": "2026-09-28T09:00:00Z"}
    }'

  log_success "Datos Retail cargados (cliente: CUS-1001, pedido: ORD-1001)."
}

# -----------------------------------------------------------------------------
# Datos Banca — cliente CUS-2001, tarjeta CARD-4455, 2 transacciones
# -----------------------------------------------------------------------------
seed_banking() {
  local table="$1"

  log_info "Cargando datos Banca..."

  # Perfil del cliente Banca
  aws dynamodb put-item \
    --table-name "${table}" \
    --item '{
      "PK":          {"S": "CUSTOMER#CUS-2001"},
      "SK":          {"S": "PROFILE"},
      "customer_id": {"S": "CUS-2001"},
      "name":        {"S": "Martín Fernández"},
      "email":       {"S": "martin.fernandez@example.com"},
      "domain":      {"S": "BANKING"},
      "created_at":  {"S": "2025-03-10T08:30:00Z"}
    }'

  # Tarjeta CARD-4455 (status: ACTIVE)
  aws dynamodb put-item \
    --table-name "${table}" \
    --item '{
      "PK":          {"S": "CUSTOMER#CUS-2001"},
      "SK":          {"S": "CARD#CARD-4455"},
      "GSI1PK":      {"S": "CARD#CARD-4455"},
      "GSI1SK":      {"S": "CUSTOMER#CUS-2001"},
      "card_id":     {"S": "CARD-4455"},
      "customer_id": {"S": "CUS-2001"},
      "last_four":   {"S": "4455"},
      "status":      {"S": "ACTIVE"},
      "card_type":   {"S": "CREDIT"},
      "created_at":  {"S": "2025-03-10T08:30:00Z"}
    }'

  # Transacción TXN-9001 (normal)
  aws dynamodb put-item \
    --table-name "${table}" \
    --item '{
      "PK":          {"S": "CUSTOMER#CUS-2001"},
      "SK":          {"S": "TXN#TXN-9001"},
      "GSI1PK":      {"S": "TXN#TXN-9001"},
      "GSI1SK":      {"S": "CUSTOMER#CUS-2001"},
      "txn_id":      {"S": "TXN-9001"},
      "customer_id": {"S": "CUS-2001"},
      "card_id":     {"S": "CARD-4455"},
      "merchant":    {"S": "Supermercado Norte"},
      "amount":      {"N": "45.20"},
      "currency":    {"S": "USD"},
      "date":        {"S": "2026-10-04"},
      "status":      {"S": "APPROVED"},
      "suspicious":  {"BOOL": false}
    }'

  # Transacción TXN-9002 (sospechosa)
  aws dynamodb put-item \
    --table-name "${table}" \
    --item '{
      "PK":          {"S": "CUSTOMER#CUS-2001"},
      "SK":          {"S": "TXN#TXN-9002"},
      "GSI1PK":      {"S": "TXN#TXN-9002"},
      "GSI1SK":      {"S": "CUSTOMER#CUS-2001"},
      "txn_id":      {"S": "TXN-9002"},
      "customer_id": {"S": "CUS-2001"},
      "card_id":     {"S": "CARD-4455"},
      "merchant":    {"S": "Electronics Store"},
      "amount":      {"N": "850.00"},
      "currency":    {"S": "USD"},
      "date":        {"S": "2026-10-05"},
      "status":      {"S": "APPROVED"},
      "suspicious":  {"BOOL": true}
    }'

  log_success "Datos Banca cargados (cliente: CUS-2001, tarjeta: CARD-4455, 2 transacciones)."
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  echo ""
  echo "=================================================="
  echo "  seed_data.sh — Ambiente: ${ENVIRONMENT}"
  echo "=================================================="
  echo ""

  local table_name
  table_name=$(get_table_name)
  log_info "Tabla DynamoDB: ${table_name}"

  seed_retail "${table_name}"
  seed_banking "${table_name}"

  echo ""
  log_success "Todos los datos ficticios cargados correctamente."
  echo ""
  echo "Resumen de datos disponibles:"
  echo "  Retail:  Laura Gómez   | Pedido ORD-1001  | Estado: DELAYED"
  echo "  Banca:   Martín Fernández | Tarjeta ****4455 | Estado: ACTIVE"
  echo "  Transacciones: TXN-9001 (normal), TXN-9002 (sospechosa - \$850 Electronics Store)"
  echo ""
}

main "$@"
