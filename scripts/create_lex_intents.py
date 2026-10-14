#!/usr/bin/env python3

"""
Script: create_lex_intents.py
Objetivo: Crear o ampliar intents en AWS Lex V2 para manejar variaciones de
          "quiero reportar fraude" en el bot BankingFraudBot.

Comportamiento seguro:
    - Intents nuevos: se crean copiando el `initialResponseSetting` de ReportFraud
      (code hook + EndConversation), para que Connect reciba el nombre del intent igual
      que con ReportFraud.
    - Intents existentes: se MEZCLAN las utterances (las actuales se conservan) y se
      reenvía el resto de la configuración tal cual, para no borrar code hooks.
    - Se descartan utterances duplicadas entre intents (Lex falla al compilar si hay).

Uso:
    python3 scripts/create_lex_intents.py --dry-run          # solo muestra qué haría
    python3 scripts/create_lex_intents.py                    # aplica sobre DRAFT

Requisitos:
    - boto3 >= 1.26.0
    - Credenciales AWS configuradas (perfil sandbox por defecto)
"""

import argparse
import logging
import sys

try:
    import boto3
    from botocore.exceptions import ClientError
except ImportError:
    print("❌ Error: boto3 no está instalado.")
    print("   Instala con: pip install boto3")
    sys.exit(1)

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

# Intent cuya configuración se usa como plantilla para los nuevos
TEMPLATE_INTENT = "ReportFraud"

# Campos de describe_intent que update_intent acepta de vuelta (se reenvían sin cambios)
PASSTHROUGH_FIELDS = [
    "description",
    "parentIntentSignature",
    "dialogCodeHook",
    "fulfillmentCodeHook",
    "slotPriorities",
    "intentConfirmationSetting",
    "intentClosingSetting",
    "inputContexts",
    "outputContexts",
    "kendraConfiguration",
    "initialResponseSetting",
    "qnAIntentConfiguration",
    "qInConnectIntentConfiguration",
    "intentDisplayName",
]

INTENTS_CONFIG = {
    "ReportFraud": [
        "quiero reportar un fraude",
        "hay fraude en mi cuenta",
        "sospecho de fraude",
        "reportar actividad fraudulenta",
        "tengo un fraude",
        "fraude",
        "reportar fraude",
    ],
    "ReportUnauthorized": [
        "hay un movimiento no autorizado",
        "no reconozco este cargo",
        "no autorizo este movimiento",
        "movimiento no reconocido",
        "cargo no autorizado",
        "no autorizado",
        "cargo que no hice",
        "esto no fui yo",
    ],
    "BlockCard": [
        "bloquea mi tarjeta",
        "quiero bloquear mi tarjeta",
        "bloquear mi cuenta",
        "deshabilitar mi tarjeta",
        "desactiva mi tarjeta",
        "quiero que bloquees mi tarjeta",
        "bloquea mi tarjeta por seguridad",
    ],
    "SuspiciousTransaction": [
        # "hay una transacción sospechosa" ya existe en ReportFraud: no repetir
        "movimiento sospechoso",
        "cargo sospechoso",
        "transacción extraña",
        "operación sospechosa",
        "veo un cargo que no reconozco",
        "hay cargos raros",
        "transacción anormal",
    ],
    "ReportFraudVariant": [
        "reportar un cargo fraudulento",
        "tengo fraude",
        "actividad fraudulenta en mi cuenta",
        "fraude en mi tarjeta",
        "detecté fraude",
        "creo que me han defraudado",
        "hay fraude aquí",
        "parece fraude",
    ],
}


def norm(text: str) -> str:
    """Normaliza una utterance para comparar duplicados."""
    return " ".join(text.lower().split())


class LexIntentManager:
    """Gestor para crear/ampliar intents en Lex V2."""

    def __init__(self, region: str, profile: str, dry_run: bool):
        session = boto3.Session(profile_name=profile, region_name=region)
        self.lex = session.client("lexv2-models")
        self.dry_run = dry_run

    def list_intents(self, bot_id, bot_version, locale_id) -> dict:
        """Devuelve {intentName: intentId}."""
        existing = {}
        kwargs = {"botId": bot_id, "botVersion": bot_version, "localeId": locale_id}
        while True:
            page = self.lex.list_intents(**kwargs)
            for intent in page.get("intentSummaries", []):
                existing[intent["intentName"]] = intent["intentId"]
            if not page.get("nextToken"):
                return existing
            kwargs["nextToken"] = page["nextToken"]

    def describe(self, bot_id, bot_version, locale_id, intent_id) -> dict:
        return self.lex.describe_intent(
            botId=bot_id,
            botVersion=bot_version,
            localeId=locale_id,
            intentId=intent_id,
        )

    def process(self, bot_id, bot_version, locale_id) -> None:
        if bot_version != "DRAFT":
            logger.error("Solo se pueden modificar intents en la versión DRAFT.")
            sys.exit(1)

        logger.info("=" * 50)
        logger.info(f"Bot: {bot_id} | versión: {bot_version} | locale: {locale_id}")
        logger.info(f"Modo: {'DRY-RUN (sin cambios)' if self.dry_run else 'APLICAR'}")
        logger.info("=" * 50)

        existing = self.list_intents(bot_id, bot_version, locale_id)
        logger.info(f"Intents existentes: {', '.join(sorted(existing))}")

        if TEMPLATE_INTENT not in existing:
            logger.error(f"No existe el intent plantilla '{TEMPLATE_INTENT}'. Abortando.")
            sys.exit(1)

        # Utterances ya usadas por intents que este script NO gestiona
        # (ConfirmYes, ConfirmNo, etc.) y por cualquier intent existente.
        taken = {}  # utterance normalizada -> intent dueño
        current = {}  # intentName -> describe_intent
        for name, intent_id in existing.items():
            if name == "FallbackIntent":
                continue
            current[name] = self.describe(bot_id, bot_version, locale_id, intent_id)
            for u in current[name].get("sampleUtterances", []):
                taken[norm(u["utterance"])] = name

        template = current[TEMPLATE_INTENT]
        created, updated, unchanged = 0, 0, 0

        for name, wanted in INTENTS_CONFIG.items():
            # Utterances finales = las que ya tiene (si existe) + las deseadas sin duplicar
            base = [u["utterance"] for u in current.get(name, {}).get("sampleUtterances", [])]
            final = list(base)
            for u in wanted:
                owner = taken.get(norm(u))
                if owner and owner != name:
                    logger.warning(f"  ⚠️ '{u}' ya pertenece a {owner}; se omite en {name}")
                    continue
                if norm(u) not in {norm(x) for x in final}:
                    final.append(u)
                    taken[norm(u)] = name
            added = len(final) - len(base)

            if name in existing:
                if added == 0:
                    logger.info(f"⏭️  {name}: sin cambios")
                    unchanged += 1
                    continue
                logger.info(f"✏️  {name}: +{added} utterances (total {len(final)})")
                if not self.dry_run:
                    kwargs = {
                        k: current[name][k] for k in PASSTHROUGH_FIELDS if k in current[name]
                    }
                    self.lex.update_intent(
                        botId=bot_id,
                        botVersion=bot_version,
                        localeId=locale_id,
                        intentId=existing[name],
                        intentName=name,
                        sampleUtterances=[{"utterance": u} for u in final],
                        **kwargs,
                    )
                updated += 1
            else:
                logger.info(f"🆕 {name}: crear con {len(final)} utterances")
                if not self.dry_run:
                    kwargs = {}
                    if "initialResponseSetting" in template:
                        kwargs["initialResponseSetting"] = template["initialResponseSetting"]
                    self.lex.create_intent(
                        botId=bot_id,
                        botVersion=bot_version,
                        localeId=locale_id,
                        intentName=name,
                        description=f"Variación de reporte de fraude: {name}",
                        sampleUtterances=[{"utterance": u} for u in final],
                        **kwargs,
                    )
                created += 1

        logger.info("=" * 50)
        logger.info(f"Creados: {created} | Actualizados: {updated} | Sin cambios: {unchanged}")
        if (created or updated) and not self.dry_run:
            logger.info("Siguiente: build-bot-locale y luego actualizar el alias.")


def main():
    parser = argparse.ArgumentParser(description="Crear/ampliar intents de fraude en Lex V2")
    parser.add_argument("--region", default="us-east-1")
    parser.add_argument("--profile", default="sandbox")
    parser.add_argument("--bot-id", default="NXHHCKVHHM")
    parser.add_argument("--bot-version", default="DRAFT")
    parser.add_argument("--locale-id", default="es_419")
    parser.add_argument("--dry-run", action="store_true", help="Muestra cambios sin aplicarlos")
    args = parser.parse_args()

    manager = LexIntentManager(args.region, args.profile, args.dry_run)
    try:
        manager.process(args.bot_id, args.bot_version, args.locale_id)
    except ClientError as e:
        logger.error(f"Error de AWS: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
