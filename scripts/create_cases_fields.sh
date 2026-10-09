#!/usr/bin/env bash
# =============================================================================
# create_cases_fields.sh — Crea los campos personalizados en Amazon Connect Cases
#
# Uso:
#   bash scripts/create_cases_fields.sh
# =============================================================================

set -euo pipefail

DOMAIN_ID="0c507c5e-02b9-4f30-82f9-d9cc20fac1d8"
REGION="us-east-1"
PROFILE="sandbox"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Variables para guardar los field_ids
FID_customerId=""
FID_transactionId=""
FID_cardReference=""
FID_blockResult=""
FID_blockedAt=""
FID_consent=""
FID_operationId=""
FID_priority=""
FID_contactId=""

# -----------------------------------------------------------------------------
# Función para crear un campo y devolver su ID
# -----------------------------------------------------------------------------
create_field() {
  local field_name="$1"
  local field_type="$2"
  local description="$3"

  log_info "Creando campo: ${field_name} (tipo: ${field_type})..."

  local response
  response=$(aws connectcases create-field \
    --domain-id "${DOMAIN_ID}" \
    --name "${field_name}" \
    --type "${field_type}" \
    --description "${description}" \
    --region "${REGION}" \
    --profile "${PROFILE}" \
    --output json)

  local field_id
  field_id=$(echo "${response}" | python3 -c "import sys,json; print(json.load(sys.stdin)['fieldId'])")

  log_success "${field_name} → ${field_id}"
  echo "${field_id}"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  echo ""
  echo "=================================================="
  echo "  create_cases_fields.sh — Dominio: ${DOMAIN_ID}"
  echo "=================================================="
  echo ""

  FID_customerId=$(create_field    "customerId"    "Text" "ID del cliente que reporta el fraude")
  FID_transactionId=$(create_field "transactionId" "Text" "ID de la transaccion sospechosa")
  FID_cardReference=$(create_field "cardReference" "Text" "Referencia enmascarada de la tarjeta (ej: ****4455)")
  FID_blockResult=$(create_field   "blockResult"   "Text" "Resultado del bloqueo: BLOCKED, ALREADY_BLOCKED, FAILED, NOT_AUTHORIZED")
  FID_blockedAt=$(create_field     "blockedAt"     "Text" "Timestamp ISO 8601 del momento del bloqueo")
  FID_consent=$(create_field       "consent"       "Text" "Consentimiento del cliente para bloquear: true o false")
  FID_operationId=$(create_field   "operationId"   "Text" "ID unico de la operacion (ej: FRAUD-CUS-2001-TXN-9002)")
  FID_priority=$(create_field      "priority"      "Text" "Prioridad del caso: HIGH, MEDIUM, LOW")
  FID_contactId=$(create_field     "contactId"     "Text" "ID del contacto de Amazon Connect asociado al caso")

  echo ""
  echo "=================================================="
  echo "  RESUMEN — Field IDs obtenidos"
  echo "=================================================="
  echo ""
  echo "  customerId    = ${FID_customerId}"
  echo "  transactionId = ${FID_transactionId}"
  echo "  cardReference = ${FID_cardReference}"
  echo "  blockResult   = ${FID_blockResult}"
  echo "  blockedAt     = ${FID_blockedAt}"
  echo "  consent       = ${FID_consent}"
  echo "  operationId   = ${FID_operationId}"
  echo "  priority      = ${FID_priority}"
  echo "  contactId     = ${FID_contactId}"

  echo ""
  echo "=================================================="
  echo "  JSON para terraform.tfvars (cases_field_ids)"
  echo "=================================================="
  echo ""
  echo "cases_field_ids = '{\"customerId\":\"${FID_customerId}\",\"transactionId\":\"${FID_transactionId}\",\"cardReference\":\"${FID_cardReference}\",\"blockResult\":\"${FID_blockResult}\",\"blockedAt\":\"${FID_blockedAt}\",\"consent\":\"${FID_consent}\",\"operationId\":\"${FID_operationId}\",\"priority\":\"${FID_priority}\",\"contactId\":\"${FID_contactId}\"}'"
  echo ""

  log_success "Todos los campos creados correctamente."
}

main "$@"
