#!/bin/bash
# Strict Mode
set -euo pipefail

# API: ACTIVE_MODULES enthaelt alle ausgewaehlten Module (komma-separiert)
# Wenn Nextcloud nicht dabei ist, entfernen wir die Storage Box.

if [[ ",$ACTIVE_MODULES," != *",nextcloud,"* ]]; then
    echo ""
    echo "[!] WARNUNG: Storage Box ohne Nextcloud hat keinen Effekt."
    echo "    Die Storage Box wird nur als Nextcloud-Datenspeicher genutzt."
    echo "    Storage Box wird aus der Auswahl entfernt."
    exit 1
fi

exit 0
