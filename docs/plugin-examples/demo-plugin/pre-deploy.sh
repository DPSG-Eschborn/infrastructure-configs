#!/bin/bash
# Strict Mode
set -euo pipefail

# Phase 5: Pre-Deploy
# Läuft kurz BEVOR docker compose up -d gestartet wird.
# Ideal für Host-System Konfigurationen.

echo "    [Demo-Plugin] Führe Host-Konfiguration durch..."

# Beispiel: Dateisystem anpassen
TARGET_DIR="/opt/pfadfinder-cloud/demo-data"
if [ ! -d "$TARGET_DIR" ]; then
    mkdir -p "$TARGET_DIR"
fi

# Idempotenz beachten:
if ! grep -q "demo-plugin-alias" /root/.bashrc 2>/dev/null; then
    echo "alias demo-plugin-alias='echo Hallo'" >> /root/.bashrc
fi

exit 0
