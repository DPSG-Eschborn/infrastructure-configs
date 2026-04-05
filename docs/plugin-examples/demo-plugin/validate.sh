#!/bin/bash
# trict Mode
set -euo pipefail

# Phase 2: Validate
# Entscheidet, ob das Modul überhaupt installiert werden *darf*.
# Return 0 bedeutet "Ist erlaubt", Return 1 wirft das Modul aus dem Installationslauf.

# Welche Variablen habe ich?
# $ACTIVE_MODULES   -> Alle ausgewählten Module als String (z.B. "core,nextcloud,demo_plugin")
# $SYSTEM_DOMAIN    -> Die eingestellte Domain (z.B. "dpsg-muster.de")

echo "    [Demo-Plugin] Prüfe Abhängigkeiten..."

# Beispiel: Dieses Modul verweigert die Installation komplett, 
# wenn der Nutzer die .nip.io Test-Domain gewählt hat.
if [[ "$SYSTEM_DOMAIN" == *.nip.io ]]; then
    echo "[!] WARNUNG: Das Demo-Plugin funktioniert nicht im Test-Modus."
    echo "    Das Modul wird für diesen Durchlauf deaktiviert."
    exit 1
fi

# Beispiel: Harte Abhängigkeit zu einem anderen Modul
if [[ ",$ACTIVE_MODULES," != *",core,"* ]]; then
    echo "[!] WARNUNG: Demo-Plugin benötigt zwingend 'core'. Wird deaktiviert."
    exit 1
fi

# Alles in Ordnung
exit 0
