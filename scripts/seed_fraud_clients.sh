#!/usr/bin/env bash
# =============================================================================
# seed_fraud_clients.sh — Carga clientes de prueba con movimientos sospechosos
#
# Uso:
#   bash scripts/seed_fraud_clients.sh [sandbox]
#
# Clientes creados (todos con al menos una transacción sospechosa):
#   CUS-3001  Ana Torres        CARD-1111  TXN-8001 $1,200 Apple Store
#   CUS-3002  Carlos Mendoza    CARD-2222  TXN-8010 $3,500 Luxury Travel
#   CUS-3003  María Rodríguez   CARD-3333  TXN-8020 $220  Amazon (sospechosa repetida)
#   CUS-3004  Jorge Vázquez     CARD-4444  TXN-8030 TARJETA YA BLOQUEADA (prueba de estado)
#   CUS-3005  Laura Castillo    CARD-5555  TXN-8040 $890  Electronics Online
# =============================================================================

set -euo pipefail

ENVIRONMENT="${1:-sandbox}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_ENV_DIR="${ROOT_DIR}/infra/environments/${ENVIRONMENT}"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }

get_table_name() {
  cd "${INFRA_ENV_DIR}"
  terraform output -raw dynamodb_table_name 2>/dev/null || {
    log_error "No se pudo obtener el nombre de la tabla desde terraform output."
    log_error "Asegúrate de haber ejecutado terraform apply primero."
    exit 1
  }
}

# -----------------------------------------------------------------------------
# Helper: cargar un cliente completo
# put_client TABLE CUS_ID NAME EMAIL CARD_ID LAST4
# -----------------------------------------------------------------------------
put_profile() {
  local table="$1" cus_id="$2" name="$3" email="$4"

  aws dynamodb put-item \
    --table-name "${table}" \
    --item "{
      \"PK\":          {\"S\": \"CUSTOMER#${cus_id}\"},
      \"SK\":          {\"S\": \"PROFILE\"},
      \"customer_id\": {\"S\": \"${cus_id}\"},
      \"name\":        {\"S\": \"${name}\"},
      \"email\":       {\"S\": \"${email}\"},
      \"domain\":      {\"S\": \"BANKING\"},
      \"created_at\":  {\"S\": \"2026-01-10T08:00:00Z\"}
    }" \
    --profile sandbox
}

put_card() {
  local table="$1" cus_id="$2" card_id="$3" last4="$4" status="$5"

  aws dynamodb put-item \
    --table-name "${table}" \
    --item "{
      \"PK\":          {\"S\": \"CUSTOMER#${cus_id}\"},
      \"SK\":          {\"S\": \"CARD#${card_id}\"},
      \"GSI1PK\":      {\"S\": \"CARD#${card_id}\"},
      \"GSI1SK\":      {\"S\": \"CUSTOMER#${cus_id}\"},
      \"card_id\":     {\"S\": \"${card_id}\"},
      \"customer_id\": {\"S\": \"${cus_id}\"},
      \"last_four\":   {\"S\": \"${last4}\"},
      \"status\":      {\"S\": \"${status}\"},
      \"card_type\":   {\"S\": \"CREDIT\"},
      \"created_at\":  {\"S\": \"2026-01-10T08:00:00Z\"}
    }" \
    --profile sandbox
}

put_txn() {
  local table="$1" cus_id="$2" txn_id="$3" card_id="$4" \
        merchant="$5" amount="$6" date="$7" suspicious="$8"

  aws dynamodb put-item \
    --table-name "${table}" \
    --item "{
      \"PK\":          {\"S\": \"CUSTOMER#${cus_id}\"},
      \"SK\":          {\"S\": \"TXN#${txn_id}\"},
      \"GSI1PK\":      {\"S\": \"TXN#${txn_id}\"},
      \"GSI1SK\":      {\"S\": \"CUSTOMER#${cus_id}\"},
      \"txn_id\":      {\"S\": \"${txn_id}\"},
      \"customer_id\": {\"S\": \"${cus_id}\"},
      \"card_id\":     {\"S\": \"${card_id}\"},
      \"merchant\":    {\"S\": \"${merchant}\"},
      \"amount\":      {\"N\": \"${amount}\"},
      \"currency\":    {\"S\": \"USD\"},
      \"date\":        {\"S\": \"${date}\"},
      \"status\":      {\"S\": \"APPROVED\"},
      \"suspicious\":  {\"BOOL\": ${suspicious}}
    }" \
    --profile sandbox
}

# =============================================================================
# Clientes de prueba
# =============================================================================

seed_client_3001() {
  local table="$1"
  log_info "CUS-3001 — Ana Torres | tarjeta CARD-1111 | cargo $1,200 Apple Store"

  put_profile "${table}" "CUS-3001" "Ana Torres" "ana.torres@example.com"
  put_card    "${table}" "CUS-3001" "CARD-1111" "1111" "ACTIVE"

  # Transacción normal
  put_txn "${table}" "CUS-3001" "TXN-8000" "CARD-1111" "Farmacia Central" "45.00" "2026-10-07" "false"

  # Transacción sospechosa — cargo alto en tienda de electrónicos
  put_txn "${table}" "CUS-3001" "TXN-8001" "CARD-1111" "Apple Store Miami" "1200.00" "2026-10-08" "true"

  log_success "CUS-3001 listo."
}

seed_client_3002() {
  local table="$1"
  log_info "CUS-3002 — Carlos Mendoza | tarjeta CARD-2222 | cargo $3,500 agencia de viajes"

  put_profile "${table}" "CUS-3002" "Carlos Mendoza" "carlos.mendoza@example.com"
  put_card    "${table}" "CUS-3002" "CARD-2222" "2222" "ACTIVE"

  put_txn "${table}" "CUS-3002" "TXN-8009" "CARD-2222" "Supermercado Express" "78.50" "2026-10-06" "false"

  # Transacción sospechosa — cargo internacional alto
  put_txn "${table}" "CUS-3002" "TXN-8010" "CARD-2222" "Luxury Travel Agency" "3500.00" "2026-10-08" "true"

  log_success "CUS-3002 listo."
}

seed_client_3003() {
  local table="$1"
  log_info "CUS-3003 — María Rodríguez | tarjeta CARD-3333 | múltiples cargos Amazon"

  put_profile "${table}" "CUS-3003" "María Rodríguez" "maria.rodriguez@example.com"
  put_card    "${table}" "CUS-3003" "CARD-3333" "3333" "ACTIVE"

  put_txn "${table}" "CUS-3003" "TXN-8019" "CARD-3333" "Amazon" "35.00" "2026-10-05" "false"

  # Cargo sospechoso — Amazon pero monto inusual para el perfil
  put_txn "${table}" "CUS-3003" "TXN-8020" "CARD-3333" "Amazon Marketplace" "220.00" "2026-10-08" "true"

  log_success "CUS-3003 listo."
}

seed_client_3004() {
  local table="$1"
  log_info "CUS-3004 — Jorge Vázquez | tarjeta CARD-4444 | TARJETA YA BLOQUEADA (prueba)"

  put_profile "${table}" "CUS-3004" "Jorge Vázquez" "jorge.vazquez@example.com"

  # Tarjeta ya bloqueada — prueba el path ALREADY_BLOCKED en block-card
  put_card "${table}" "CUS-3004" "CARD-4444" "4444" "BLOCKED"

  put_txn "${table}" "CUS-3004" "TXN-8029" "CARD-4444" "Gas Station" "55.00" "2026-10-04" "false"
  put_txn "${table}" "CUS-3004" "TXN-8030" "CARD-4444" "International Wire" "750.00" "2026-10-08" "true"

  log_success "CUS-3004 listo. (tarjeta bloqueada — prueba ALREADY_BLOCKED)"
}

seed_client_3005() {
  local table="$1"
  log_info "CUS-3005 — Laura Castillo | tarjeta CARD-5555 | cargo $890 Electronics"

  put_profile "${table}" "CUS-3005" "Laura Castillo" "laura.castillo@example.com"
  put_card    "${table}" "CUS-3005" "CARD-5555" "5555" "ACTIVE"

  put_txn "${table}" "CUS-3005" "TXN-8039" "CARD-5555" "Restaurante El Gaucho" "62.00" "2026-10-07" "false"

  # Transacción sospechosa
  put_txn "${table}" "CUS-3005" "TXN-8040" "CARD-5555" "Electronics Online Store" "890.00" "2026-10-09" "true"

  log_success "CUS-3005 listo."
}

# =============================================================================
# Main
# =============================================================================
main() {
  echo ""
  echo "=================================================="
  echo "  seed_fraud_clients.sh — Ambiente: ${ENVIRONMENT}"
  echo "=================================================="
  echo ""

  local table_name
  table_name=$(get_table_name)
  log_info "Tabla DynamoDB: ${table_name}"
  echo ""

  seed_client_3001 "${table_name}"
  seed_client_3002 "${table_name}"
  seed_client_3003 "${table_name}"
  seed_client_3004 "${table_name}"
  seed_client_3005 "${table_name}"

  echo ""
  log_success "Todos los clientes de prueba cargados."
  echo ""
  echo "Resumen de clientes para probar el flujo V3:"
  echo "────────────────────────────────────────────────────────────────"
  echo "  ID        Nombre              Tarjeta    Monto sospechoso   Notas"
  echo "  CUS-3001  Ana Torres          ****1111   \$1,200 Apple Store"
  echo "  CUS-3002  Carlos Mendoza      ****2222   \$3,500 Luxury Travel"
  echo "  CUS-3003  María Rodríguez     ****3333   \$220  Amazon"
  echo "  CUS-3004  Jorge Vázquez       ****4444   \$750  Wire        ← tarjeta ya BLOQUEADA"
  echo "  CUS-3005  Laura Castillo      ****5555   \$890  Electronics"
  echo "────────────────────────────────────────────────────────────────"
  echo ""
  echo "Tip: CUS-3004 prueba el path blockResult=ALREADY_BLOCKED."
  echo ""
}

main "$@"
