#!/bin/bash

##############################################################################
# Script: add-fraud-intents.sh
# Objetivo: Agregar más intents a Lex para manejar variaciones de 
#           "quiero reportar fraude" en el bot BankingFraudBot
# 
# Uso:
#   ./scripts/add-fraud-intents.sh [--region us-east-1] [--profile sandbox] [--dry-run]
#
# Intents que se crean:
#   - ReportFraud (ya existe, se valida)
#   - ReportUnauthorized (movimiento no autorizado)
#   - BlockCard (solicitud de bloqueo de tarjeta)
#   - SuspiciousTransaction (transacción sospechosa)
#   - ReportFraudVariant (variación general)
##############################################################################

set -e

# Configuración por defecto
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_PROFILE="${AWS_PROFILE:-sandbox}"
DRY_RUN=false

# Parsear argumentos
while [[ $# -gt 0 ]]; do
  case $1 in
    --region)
      AWS_REGION="$2"
      shift 2
      ;;
    --profile)
      AWS_PROFILE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      echo "Opción desconocida: $1"
      exit 1
      ;;
  esac
done

# Configurar AWS CLI
export AWS_REGION
export AWS_PROFILE

echo "=========================================="
echo "Bot Lex: Agregar intents para fraude"
echo "=========================================="
echo "Región: $AWS_REGION"
echo "Perfil: $AWS_PROFILE"
echo "Dry Run: $DRY_RUN"
echo ""

# IDs del bot (del archivo contexto-v3.md)
BOT_ID="NXHHCKVHHM"
ALIAS_ID="ZSII5DJKMX"
LOCALE_ID="es_419"  # Lex usa es_419 en vez de es-419

echo "📋 Verificando bot..."
BOT_INFO=$(aws lex describe-bots \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --query "botSummaries[?botId=='$BOT_ID']" \
  --output json)

if [ -z "$BOT_INFO" ] || [ "$BOT_INFO" == "[]" ]; then
  echo "❌ Bot no encontrado: $BOT_ID"
  exit 1
fi

echo "✅ Bot encontrado: BankingFraudBot ($BOT_ID)"
echo ""

# Obtener la versión del bot
BOT_VERSION=$(aws lex describe-bots \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --bot-id "$BOT_ID" \
  --query 'botSummaries[0].latestBotVersion' \
  --output text)

echo "📦 Versión del bot: $BOT_VERSION"

# Listar intents actuales
echo ""
echo "📝 Intents actuales:"
aws lex list-intents \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --bot-id "$BOT_ID" \
  --bot-version "$BOT_VERSION" \
  --locale-id "$LOCALE_ID" \
  --query 'intentSummaries[*].[intentName, intentId]' \
  --output table

# Definir los intents a crear
declare -a INTENTS=(
  "ReportFraud"
  "ReportUnauthorized"
  "BlockCard"
  "SuspiciousTransaction"
  "ReportFraudVariant"
)

# Mapeo de intents a utterances (ejemplos de usuario)
declare -A UTTERANCES=(
  ["ReportFraud"]="quiero reportar un fraude|hay fraude en mi cuenta|sospechos de fraude|reportar actividad fraudulenta"
  ["ReportUnauthorized"]="hay un movimiento no autorizado|no reconozco este cargo|no autorizo este movimiento|movimiento no reconocido"
  ["BlockCard"]="bloquea mi tarjeta|quiero bloquear mi tarjeta|bloquear mi cuenta|deshabilitar mi tarjeta"
  ["SuspiciousTransaction"]="hay una transacción sospechosa|movimiento sospechoso|cargo sospechoso|transacción extraña"
  ["ReportFraudVariant"]="reportar un cargo fraudulento|tengo fraude|actividad fraudulenta en mi cuenta|fraude en mi tarjeta"
)

echo ""
echo "🔧 Procesando intents..."
echo ""

# Para cada intent, verificar si existe o crearlo
for intent_name in "${INTENTS[@]}"; do
  echo "Procesando intent: $intent_name"
  
  # Verificar si el intent ya existe
  EXISTING_INTENT=$(aws lex list-intents \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    --bot-id "$BOT_ID" \
    --bot-version "$BOT_VERSION" \
    --locale-id "$LOCALE_ID" \
    --query "intentSummaries[?intentName=='$intent_name'].intentId" \
    --output text 2>/dev/null || true)
  
  if [ -n "$EXISTING_INTENT" ]; then
    echo "  ✅ Intent ya existe: $EXISTING_INTENT"
  else
    echo "  ⚠️  Intent no existe. En Lex v2, los intents deben crearse desde la consola o con SDK."
    echo "     No se puede crear vía AWS CLI directamente."
    echo "     Se recomienda usar la consola de AWS Lex para crear este intent."
  fi
  
  # Mostrar sample utterances para este intent
  utterances="${UTTERANCES[$intent_name]}"
  echo "  📢 Sample Utterances recomendadas:"
  IFS='|' read -ra UARRAY <<< "$utterances"
  for utt in "${UARRAY[@]}"; do
    echo "     - $utt"
  done
  echo ""
done

echo ""
echo "=========================================="
echo "ℹ️  IMPORTANTE - Próximos pasos:"
echo "=========================================="
echo ""
echo "Los intents en AWS Lex v2 NO pueden crearse directamente con AWS CLI."
echo "Debes crearlos desde la consola de AWS o usar el SDK de boto3/JavaScript."
echo ""
echo "Pasos recomendados:"
echo "1. Accede a https://console.aws.amazon.com/lexv2/"
echo "2. Selecciona el bot 'BankingFraudBot' ($BOT_ID)"
echo "3. Ve a 'Intents' en el panel izquierdo"
echo "4. Crea o modifica los siguientes intents:"
echo ""
for intent_name in "${INTENTS[@]}"; do
  utterances="${UTTERANCES[$intent_name]}"
  echo "   • $intent_name"
  IFS='|' read -ra UARRAY <<< "$utterances"
  for utt in "${UARRAY[@]}"; do
    echo "     - $utt"
  done
  echo ""
done
echo "5. Crea una versión nueva del bot (Build)"
echo "6. Crea un alias nuevo o actualiza 'SandboxBanking' ($ALIAS_ID)"
echo ""
echo "Para automatizar esto, considera usar AWS CDK o terraform-aws-modules."
echo ""
