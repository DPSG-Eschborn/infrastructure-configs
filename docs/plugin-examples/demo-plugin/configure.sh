#!/bin/bash
# Strict Mode
set -euo pipefail

# Phase 3: Configure
# Läuft NUR, wenn das Setup im INTERAKTIVEN Modus gestartet wird.
# Headless-Skripte rufen diesen Hook nie auf.

# Welche Variablen habe ich?
# $ASSISTANT_MODE  -> Immer "interactive" an dieser Stelle
# $MODULE_ENV_FILE -> Ein temporärer Datei-Pfad, in den wir Variablen für setup.sh übergeben können.

echo ""
echo "========================================="
echo "   Demo-Plugin spezielle Einstellungen"
echo "========================================="
echo ""

read -p "Demo-Plugin Admin Username eingeben: " DEMO_USER
read -s -p "Admin Passwort vergeben: " DEMO_PASS
echo ""

# Validierung der User-Eingabe
if [ -z "$DEMO_USER" ] || [ -z "$DEMO_PASS" ]; then
    echo "[!] Eingabe fehlgeschlagen. Überspringe das Demo-Plugin."
    exit 1
fi

# Hier sprechen wir mit setup.sh!
# Alles was wir in $MODULE_ENV_FILE schreiben, lernt setup.sh für alle weiteren Schritte.
# Diese Variablen wandern dann automatisch als Such-Muster in die .env.example
echo "DEMO_ADMIN_USER=$DEMO_USER" >> "$MODULE_ENV_FILE"
echo "DEMO_ADMIN_PASS=$DEMO_PASS" >> "$MODULE_ENV_FILE"

exit 0
