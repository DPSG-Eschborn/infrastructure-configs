#!/bin/bash
# P10 Strict Mode: Beendet das Skript sofort bei Fehlern, ungesetzten Variablen oder Pipe-Fehlern
set -euo pipefail

# Sicherstellen, dass das Skript root-Rechte hat (EUID 0)
if [[ $EUID -ne 0 ]]; then
   echo "[!] Docker und Systemkonfigurationen erfordern Root-Rechte."
   echo "Bitte starte das Skript mit: sudo ./setup.sh"
   exit 1
fi

MODE="interactive"
INSTALL_MODULES=()
DOMAIN=""

# Parameter verarbeiten (Headless Mode Handler)
for arg in "$@"; do
    case $arg in
        --interactive) MODE="interactive" ;;
        --headless) MODE="headless" ;;
        --install=*)
            # Kommagetrennte Liste in Array verwandeln
            IFS=',' read -ra ADDR <<< "${arg#*=}"
            for i in "${ADDR[@]}"; do
                INSTALL_MODULES+=("$i")
            done
            ;;
        --domain=*) DOMAIN="${arg#*=}" ;;
    esac
done

echo "========================================="
echo "   Pfadfinder Cloud Setup-Engine"
echo "========================================="
echo "Modus: $MODE"

# 1. Automatisches Installieren von Docker (Idempotent)
if ! command -v docker &> /dev/null; then
    echo "[+] Docker nicht gefunden. Installiere offizielles Docker-Engine..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    echo "[+] Docker wurde erfolgreich installiert."
else
    echo "[OK] Docker ist bereits installiert. (Idempotenz Check bestanden)"
fi

# 2. Plugin-System initialisieren (Auto-Erkennung)
declare -A PLUGINS_NAME
declare -A PLUGINS_DESC
declare -A PLUGINS_PATH
AVAILABLE_MODULES=()

echo "[-] Scanne nach Modulen in /core/ und /extensions/..."

# Gehe durch alle manifest.env Dateien in allen Ordnern
shopt -s nullglob
for manifest in ./core/*/manifest.env ./extensions/*/manifest.env; do
    if [ -f "$manifest" ]; then
        # Sourcen (sicher) um die Variablen zu laden
        source "$manifest"
        
        # In Arrays abspeichern
        PLUGINS_NAME[$MODULE_ID]="$MODULE_NAME"
        PLUGINS_DESC[$MODULE_ID]="$MODULE_DESCRIPTION"
        PLUGINS_PATH[$MODULE_ID]="$(dirname "$manifest")"
        AVAILABLE_MODULES+=("$MODULE_ID")
        
        echo "    -> Gefunden: $MODULE_NAME ($MODULE_ID) - $MODULE_DESCRIPTION"
    fi
done
shopt -u nullglob

# 3. Interaktives Menü (falls nicht Headless)
if [ "$MODE" = "interactive" ]; then
    echo ""
    read -p "Welche Basis-Domain möchtest du konfigurieren? (z.B. cloud.pfadi.de): " DOMAIN_INPUT
    if [ -n "$DOMAIN_INPUT" ]; then
        DOMAIN="$DOMAIN_INPUT"
    fi
    
    echo ""
    echo "--- Modul Aktivierung ---"
    for mod in "${AVAILABLE_MODULES[@]}"; do
        read -p "[?] Installiere ${PLUGINS_NAME[$mod]}? (y/n): " choice
        case "$choice" in 
          y|Y ) INSTALL_MODULES+=("$mod");;
          * ) echo "    Überspringe $mod.";;
        esac
    done
fi

if [ -z "$DOMAIN" ]; then
    echo "[!] FEHLER: Keine Domain angegeben. Wir können SSL-Zertifikate sonst nicht routen."
    exit 1
fi

# 4. Konstantes Deployment Network erstellen
echo ""
echo "[-] Prüfe Docker-Netzwerk..."
if ! docker network ls | grep -q "pfadfinder_net"; then
    docker network create pfadfinder_net
    echo "    -> Netzwerk 'pfadfinder_net' erstellt."
else
    echo "    -> Netzwerk existiert bereits."
fi

# 5. Deployment durchlaufen
echo ""
echo "Starte Deployment Prozess für: ${INSTALL_MODULES[*]:-Keine ausgewählt}"

for mod in "${INSTALL_MODULES[@]:-}"; do
    # Existiert das Modul in unseren ausgelesenen Plugins?
    if [[ -n "${PLUGINS_PATH[$mod]:-}" ]]; then
        MOD_PATH="${PLUGINS_PATH[$mod]}"
        echo "========================================="
        echo "[+] Aktiviere Modul: ${PLUGINS_NAME[$mod]}"
        
        ENV_FILE="$MOD_PATH/.env"
        
        # P10 Standard: Atomic Write von Konfigurationsdateien
        if [ ! -f "$ENV_FILE" ]; then
            if [ -f "$MOD_PATH/.env.example" ]; then
                TMP_ENV="$MOD_PATH/.env.tmp"
                cp "$MOD_PATH/.env.example" "$TMP_ENV"
                
                # Injection: Platzhalter mit Werten ersetzen
                sed -i "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" "$TMP_ENV"
                
                # Wenn Passwörter gefordert werden, sichere zufällige Passwörter generieren
                RANDOM_PW=$(openssl rand -hex 16)
                sed -i "s/PASSWORD_PLACEHOLDER/$RANDOM_PW/g" "$TMP_ENV"
                
                # Atomares Verschieben
                mv "$TMP_ENV" "$ENV_FILE"
                echo "    -> Konfiguration (.env) dynamisch generiert."
            fi
        else
            echo "    -> Modul wurde bereis früher konfiguriert (.env existiert). Überspring Generierung."
        fi
        
        # P10 Standard: Idempotenz (up -d startet nur neu, wenn sich das image ändert)
        echo "    -> Starte Container..."
        cd "$MOD_PATH"
        docker compose up -d | sed 's/^/       /'
        cd - > /dev/null
    else
        echo "[!] WARNUNG: Das angeforderte Modul '$mod' existiert nicht. Ignoriere."
    fi
done

echo ""
echo "========================================="
echo "Setup abgeschlossen"
echo "Basis-Domain: $DOMAIN"
echo "========================================="
