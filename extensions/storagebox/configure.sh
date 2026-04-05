#!/bin/bash
# P10 Strict Mode
set -euo pipefail

# API:
# IN:  ASSISTANT_MODE, MODULE_ENV_FILE
# OUT: Schreibt Konfiguration in MODULE_ENV_FILE

if [ "${ASSISTANT_MODE:-interactive}" != "interactive" ]; then
    # Im Headless-Modus muessen STORAGEBOX_USER und STORAGEBOX_PASS
    # bereits als Environment-Variablen beim Aufruf von setup.sh existieren.
    # Wenn sie existieren, setzen wir CUSTOM_DATA_DIR.
    if [ -n "${STORAGEBOX_USER:-}" ] && [ -n "${STORAGEBOX_PASS:-}" ]; then
        echo "CUSTOM_DATA_DIR=/mnt/storagebox-data" >> "$MODULE_ENV_FILE"
    fi
    exit 0
fi

# Interaktiver Modus
echo ""
echo "============================================"
echo "   Hetzner Storage Box Konfiguration"
echo "============================================"
echo ""
echo "WICHTIG: Stelle sicher, dass SMB-Support in der Hetzner Console"
echo "aktiviert ist, bevor du fortfaehrst!"
echo "(Hetzner Console -> Storage Box -> Einstellungen -> Samba aktivieren)"
echo ""
read -p "Dein Storage Box Username (z.B. u123456): " INPUT_USER
read -s -p "Dein Storage Box Passwort: " INPUT_PASS
echo ""

if [ -z "$INPUT_USER" ] || [ -z "$INPUT_PASS" ]; then
    echo "[!] Kein Username oder Passwort eingegeben. Storage Box wird uebersprungen."
    # Ueberspringen = wir geben exit 1 (Validation failed bei interaktiver Abfrage)
    exit 1
else
    echo "[OK] Storage Box Zugangsdaten erfasst."
    
    # In die Env-Datei schreiben, die von setup.sh ausgelesen wird
    echo "STORAGEBOX_USER=$INPUT_USER" >> "$MODULE_ENV_FILE"
    echo "STORAGEBOX_PASS=$INPUT_PASS" >> "$MODULE_ENV_FILE"
    echo "CUSTOM_DATA_DIR=/mnt/storagebox-data" >> "$MODULE_ENV_FILE"
fi
