#!/usr/bin/env bash
# =============================================================================
# destroy.sh — Destruye el ambiente de la demo Amazon Connect
#
# Uso:
#   bash scripts/destroy.sh [sandbox]
#
# ADVERTENCIA: Este script elimina todos los recursos Terraform del ambiente.
# Algunos recursos pueden requerir eliminación manual (ver salida del script).
# =============================================================================

set -euo pipefail

ENVIRONMENT="${1:-sandbox}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_ENV_DIR="${ROOT_DIR}/infra/environments/${ENVIRONMENT}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# -----------------------------------------------------------------------------
# Confirmación explícita antes de destruir
# -----------------------------------------------------------------------------
confirm_destroy() {
  echo ""
  echo -e "${RED}=================================================="
  echo "  ⚠️  ADVERTENCIA: OPERACIÓN DESTRUCTIVA"
  echo "=================================================="
  echo -e "${NC}"
  echo "Este script eliminará TODOS los recursos Terraform del ambiente '${ENVIRONMENT}':"
  echo "  - Instancia Amazon Connect (queues, flows, usuarios)"
  echo "  - Agente Bedrock (AgentCore)"
  echo "  - Funciones Lambda"
  echo "  - Tabla DynamoDB (incluyendo todos los datos)"
  echo "  - Roles y políticas IAM"
  echo "  - Log Groups de CloudWatch"
  echo "  - Dashboard y alarmas CloudWatch"
  echo ""
  log_warning "Esta acción NO puede deshacerse fácilmente."
  echo ""
  read -rp "Escribe 'DESTRUIR' para confirmar: " confirm
  if [[ "${confirm}" != "DESTRUIR" ]]; then
    log_info "Operación cancelada."
    exit 0
  fi
}

# -----------------------------------------------------------------------------
# Destruir el ambiente
# -----------------------------------------------------------------------------
destroy_environment() {
  log_info "Destruyendo ambiente '${ENVIRONMENT}'..."

  if [[ ! -d "${INFRA_ENV_DIR}" ]]; then
    log_error "No existe el directorio: ${INFRA_ENV_DIR}"
    exit 1
  fi

  cd "${INFRA_ENV_DIR}"
  terraform init -input=false
  terraform destroy -input=false -auto-approve

  log_success "Ambiente '${ENVIRONMENT}' destruido."
}

# -----------------------------------------------------------------------------
# Advertencias sobre recursos residuales
# -----------------------------------------------------------------------------
show_manual_cleanup_warnings() {
  echo ""
  log_warning "Recursos que pueden requerir eliminación manual:"
  echo ""
  echo "  1. Instancia Amazon Connect"
  echo "     → Consola AWS > Amazon Connect > Instancias"
  echo "     → Eliminar si terraform destroy no la removió completamente"
  echo ""
  echo "  2. Números telefónicos reclamados"
  echo "     → Consola Connect > Phone numbers"
  echo "     → Liberar antes de eliminar la instancia"
  echo ""
  echo "  3. CloudWatch Log Groups con retención"
  echo "     → aws logs describe-log-groups --log-group-name-prefix /connect-demo"
  echo "     → aws logs delete-log-group --log-group-name <nombre>"
  echo ""
  echo "  4. Bucket S3 del estado de Terraform (bootstrap)"
  echo "     → NO eliminar si planeas redesplegar el ambiente"
  echo "     → Si deseas eliminarlo: vaciar el bucket primero, luego borrarlo"
  echo ""
  echo "  5. Recursos AgentCore que no tengan soporte completo en Terraform"
  echo "     → Revisar consola Bedrock > Agents"
  echo ""
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  echo ""
  echo "=================================================="
  echo "  destroy.sh — Ambiente: ${ENVIRONMENT}"
  echo "=================================================="

  confirm_destroy
  destroy_environment
  show_manual_cleanup_warnings

  echo ""
  log_success "Proceso de limpieza completado."
  echo "Revisar la consola AWS para confirmar que no quedan recursos residuales."
  echo ""
}

main "$@"
