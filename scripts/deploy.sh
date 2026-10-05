#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Despliega el ambiente completo de la demo Amazon Connect
#
# Uso:
#   bash scripts/deploy.sh [sandbox]
#
# Prerrequisitos:
#   - AWS CLI configurado (aws configure)
#   - Terraform >= 1.9.5
#   - Python >= 3.11
# =============================================================================

set -euo pipefail

ENVIRONMENT="${1:-sandbox}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_ENV_DIR="${ROOT_DIR}/infra/environments/${ENVIRONMENT}"
BOOTSTRAP_DIR="${ROOT_DIR}/infra/bootstrap"

# Colores para output
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
# Verificar prerrequisitos
# -----------------------------------------------------------------------------
check_prerequisites() {
  log_info "Verificando prerrequisitos..."

  if ! command -v aws &>/dev/null; then
    log_error "AWS CLI no encontrado. Instalar desde https://aws.amazon.com/cli/"
    exit 1
  fi

  if ! command -v terraform &>/dev/null; then
    log_error "Terraform no encontrado. Instalar desde https://developer.hashicorp.com/terraform/install"
    exit 1
  fi

  if ! command -v python3 &>/dev/null; then
    log_error "Python3 no encontrado."
    exit 1
  fi

  # Verificar identidad AWS
  local account_info
  account_info=$(aws sts get-caller-identity --output json 2>/dev/null) || {
    log_error "No se pudo verificar la identidad AWS. Revisar credenciales."
    exit 1
  }

  local account_id
  account_id=$(echo "${account_info}" | python3 -c "import sys,json; print(json.load(sys.stdin)['Account'])")
  local region
  region=$(aws configure get region 2>/dev/null || echo "us-east-1")

  log_success "AWS CLI OK — Account: ${account_id} | Region: ${region}"
  log_success "Terraform $(terraform version -json | python3 -c "import sys,json; print(json.load(sys.stdin)['terraform_version'])")"
  log_success "Python $(python3 --version)"
}

# -----------------------------------------------------------------------------
# Fase 1: Bootstrap del backend de Terraform (solo si no existe)
# -----------------------------------------------------------------------------
bootstrap() {
  log_info "Fase 1: Bootstrap del backend Terraform..."

  # Verificar si el bucket ya existe intentando describir el estado
  if [[ -f "${BOOTSTRAP_DIR}/.terraform/terraform.tfstate" ]]; then
    log_warning "Bootstrap ya ejecutado anteriormente. Saltando."
    return 0
  fi

  cd "${BOOTSTRAP_DIR}"
  terraform init -input=false
  terraform apply -input=false -auto-approve

  log_success "Bootstrap completado."
}

# -----------------------------------------------------------------------------
# Fase 2: Desplegar el ambiente
# -----------------------------------------------------------------------------
deploy_environment() {
  log_info "Fase 2: Desplegando ambiente '${ENVIRONMENT}'..."

  if [[ ! -d "${INFRA_ENV_DIR}" ]]; then
    log_error "No existe el directorio de ambiente: ${INFRA_ENV_DIR}"
    exit 1
  fi

  if [[ ! -f "${INFRA_ENV_DIR}/terraform.tfvars" ]]; then
    log_warning "No se encontró terraform.tfvars en ${INFRA_ENV_DIR}"
    log_warning "Copiando terraform.tfvars.example como base..."
    cp "${INFRA_ENV_DIR}/terraform.tfvars.example" "${INFRA_ENV_DIR}/terraform.tfvars"
    log_warning "EDITAR ${INFRA_ENV_DIR}/terraform.tfvars antes de continuar."
    log_warning "En particular: connect_instance_alias debe ser único globalmente."
    read -rp "¿Deseas continuar con los valores por defecto? [s/N]: " confirm
    if [[ "${confirm}" != "s" && "${confirm}" != "S" ]]; then
      log_info "Abortando. Edita el archivo y vuelve a ejecutar el script."
      exit 0
    fi
  fi

  cd "${INFRA_ENV_DIR}"
  terraform init -input=false
  terraform plan -input=false -out=tfplan
  terraform apply -input=false tfplan
  rm -f tfplan

  log_success "Ambiente '${ENVIRONMENT}' desplegado correctamente."
}

# -----------------------------------------------------------------------------
# Fase 3: Cargar datos ficticios en DynamoDB
# -----------------------------------------------------------------------------
seed_data() {
  log_info "Fase 3: Cargando datos ficticios en DynamoDB..."
  bash "${SCRIPT_DIR}/seed_data.sh" "${ENVIRONMENT}"
  log_success "Datos ficticios cargados."
}

# -----------------------------------------------------------------------------
# Mostrar outputs relevantes
# -----------------------------------------------------------------------------
show_outputs() {
  log_info "Outputs del despliegue:"
  cd "${INFRA_ENV_DIR}"
  terraform output
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  echo ""
  echo "=================================================="
  echo "  connect-demo-infra — Despliegue: ${ENVIRONMENT}"
  echo "=================================================="
  echo ""

  check_prerequisites
  bootstrap
  deploy_environment
  seed_data
  show_outputs

  echo ""
  log_success "¡Despliegue completo!"
  echo ""
  echo "Próximos pasos manuales (si corresponden):"
  echo "  1. Acceder a la consola de Amazon Connect y verificar la instancia."
  echo "  2. Reclamar un número telefónico (opcional, puede no estar disponible en sandbox)."
  echo "  3. Publicar los Contact Flows si están en estado DRAFT."
  echo "  4. Cambiar la contraseña del agente de demo en la consola de Connect."
  echo ""
}

main "$@"
