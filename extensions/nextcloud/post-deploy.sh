#!/bin/bash
set -euo pipefail

ENV_FILE="$(dirname "$0")/.env"

if [ -f "$ENV_FILE" ]; then
    NC_PW=$(grep "NC_ADMIN_PASSWORD" "$ENV_FILE" | cut -d'=' -f2 || true)
    if [ -n "$NC_PW" ] && [ "$NC_PW" != "PASSWORD_PLACEHOLDER" ]; then
        echo ""
        echo "       * * * NEXTCLOUD ADMIN LOGIN * * *"
        echo "       Benutzer: admin"
        echo "       Passwort: $NC_PW"
        echo "       Bitte nach dem ersten Login sofort aendern!"
        echo "       * * * * * * * * * * * * * * * * * *"
        echo ""
    fi
fi
exit 0
