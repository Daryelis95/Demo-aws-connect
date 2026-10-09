#!/usr/bin/env bash
# =============================================================================
# create_cases_template.sh — Crea la plantilla "Reporte de fraude bancario"
#                            en Amazon Connect Cases
#
# Uso:
#   bash scripts/create_cases_template.sh
#
# Requisitos:
#   - AWS CLI configurado con el profile sandbox
#   - El dominio de Cases ya debe estar creado: 0c507c5e-02b9-4f30-82f9-d9cc20fac1d8
#   - Los campos personalizados ya deben estar creados (create_cases_fields.sh)
#
# Salida:
#   Imprime el templateId listo para pegar en terraform.tfvars como cases_template_id
# =============================================================================

set -euo pipefail

DOMAIN_ID="0c507c5e-02b9-4f30-82f9-d9cc20fac1d8"
REGION="us-east-1"
PROFILE="sandbox"

# Field IDs obtenidos con create_cases_fields.sh
FID_customerId="a7f0ea33-f713-4889-a76e-04e40ea97ef0"
FID_transactionId="e8281ec5-970f-4d5d-863c-56b635256cba"
FID_cardReference="1b37058d-0826-4145-beb3-bf1392ead7bf"
FID_blockResult="55d8e18f-37f6-4866-a0a5-d1d2a00403e9"
FID_blockedAt="e256b5f2-162d-4f3c-a014-3935d0981932"
FID_consent="52729c3b-3027-4bbe-a126-1136f2f83196"
FID_operationId="ec1a0b44-7e92-40a5-811c-4514025c688b"
FID_priority="e935fdd5-e770-4fd1-bf76-27c832b5cb83"
FID_contactId="5198411d-e7d8-4c11-a018-95ee78f7ebcf"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }

main() {
  echo ""
  echo "=================================================="
  echo "  create_cases_template.sh — Dominio: ${DOMAIN_ID}"
  echo "=================================================="
  echo ""

  log_info "Creando plantilla 'Reporte de fraude bancario'..."

  # Los campos requeridos son los que el agente DEBE ver al abrir el caso.
  # Se incluyen todos los campos personalizados relevantes para el agente.
  RESPONSE=$(aws connectcases create-template \
    --domain-id "${DOMAIN_ID}" \
    --name "Reporte de fraude bancario" \
    --description "Expediente de reporte de fraude generado automaticamente por el flujo de llamada V3" \
    --status "Active" \
    --required-fields \
      fieldId="${FID_customerId}" \
      fieldId="${FID_transactionId}" \
      fieldId="${FID_blockResult}" \
    --region "${REGION}" \
    --profile "${PROFILE}" \
    --output json)

  TEMPLATE_ID=$(echo "${RESPONSE}" | python3 -c "import sys,json; print(json.load(sys.stdin)['templateId'])")
  TEMPLATE_ARN=$(echo "${RESPONSE}" | python3 -c "import sys,json; print(json.load(sys.stdin)['templateArn'])")

  log_success "Plantilla creada exitosamente."
  echo ""
  echo "  templateId  = ${TEMPLATE_ID}"
  echo "  templateArn = ${TEMPLATE_ARN}"
  echo ""
  echo "=================================================="
  echo "  Línea para terraform.tfvars"
  echo "=================================================="
  echo ""
  echo "cases_template_id = \"${TEMPLATE_ID}\""
  echo ""
  echo "=================================================="
  echo "  Resumen completo para terraform.tfvars"
  echo "=================================================="
  echo ""
  echo "cases_domain_id   = \"${DOMAIN_ID}\""
  echo "cases_template_id = \"${TEMPLATE_ID}\""
  echo "cases_field_ids   = '{\"customerId\":\"${FID_customerId}\",\"transactionId\":\"${FID_transactionId}\",\"cardReference\":\"${FID_cardReference}\",\"blockResult\":\"${FID_blockResult}\",\"blockedAt\":\"${FID_blockedAt}\",\"consent\":\"${FID_consent}\",\"operationId\":\"${FID_operationId}\",\"priority\":\"${FID_priority}\",\"contactId\":\"${FID_contactId}\"}'"
  echo "customer_profiles_domain_name = \"connect-demo-banking-sandbox\""
  echo ""
  log_success "Listo. Copia las 4 líneas de arriba a terraform.tfvars."
}

main "$@"
