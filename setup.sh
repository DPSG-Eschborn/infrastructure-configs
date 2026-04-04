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
    read -p "Welche Basis-Domain möchtest du konfigurieren? (leer lassen für Test-Modus): " DOMAIN_INPUT
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

if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "AUTO" ]; then
    echo "[-] Kein Domainname übergeben (oder AUTO gesetzt). Erstelle automatische .nip.io Test-Domain..."
    PUBLIC_IP=$(curl -4 -s icanhazip.com)
    if [ -n "$PUBLIC_IP" ]; then
        DOMAIN="${PUBLIC_IP}.nip.io"
        echo "    -> Dynamische Domain generiert: $DOMAIN"
    else
        echo "[!] FEHLER: Konnte Server IP nicht ermitteln. Abbruch."
        exit 1
    fi
fi

# Test-Modus Erkennung: .nip.io Domains können kein SSL bekommen
TEST_MODE=false
if [[ "$DOMAIN" == *.nip.io ]]; then
    TEST_MODE=true
    echo ""
    echo "============================================"
    echo "[!] TEST-MODUS AKTIV"
    echo "[!] .nip.io Domain erkannt - HTTPS wird deaktiviert."
    echo "[!] SSL-Zertifikate sind nur mit einer echten Domain möglich."
    echo "[!] Alle Dienste werden über HTTP erreichbar sein."
    echo "============================================"
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
if [ ${#INSTALL_MODULES[@]} -eq 0 ]; then
    echo "Keine Module zum Installieren ausgewählt."
else
    echo "Starte Deployment Prozess für: ${INSTALL_MODULES[*]}"
fi

for mod in "${INSTALL_MODULES[@]+${INSTALL_MODULES[@]}}"; do
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
                # Jedes Vorkommen von PASSWORD_PLACEHOLDER bekommt sein eigenes Passwort
                while grep -q 'PASSWORD_PLACEHOLDER' "$TMP_ENV"; do
                    RANDOM_PW=$(openssl rand -hex 16)
                    sed -i "0,/PASSWORD_PLACEHOLDER/s/PASSWORD_PLACEHOLDER/$RANDOM_PW/" "$TMP_ENV"
                done
                
                # Atomares Verschieben
                mv "$TMP_ENV" "$ENV_FILE"
                echo "    -> Konfiguration (.env) dynamisch generiert."
            fi
        else
            echo "    -> Modul wurde bereis früher konfiguriert (.env existiert). Überspring Generierung."
        fi
        
        # Test-Modus: Compose-Dateien für HTTP-Betrieb anpassen
        if [ "$TEST_MODE" = true ]; then
            echo "    -> Test-Modus: Passe auf HTTP-Betrieb an..."
            if [ "$mod" = "core" ]; then
                # Traefik: HTTPS-Redirect deaktivieren (aber Entrypoints beibehalten)
                sed -i '/redirections/d' "$MOD_PATH/docker-compose.yml"
            else
                # Services: Entrypoint von websecure auf web (HTTP) umstellen
                sed -i 's/websecure/web/g' "$MOD_PATH/docker-compose.yml"
                # Certresolver-Labels entfernen (kein SSL ohne echte Domain)
                sed -i '/certresolver/d' "$MOD_PATH/docker-compose.yml"
            fi
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
echo "Setup abgeschlossen!"
echo "Basis-Domain: $DOMAIN"
if [ "$TEST_MODE" = true ]; then
    echo ""
    echo "Deine Dienste sind erreichbar unter:"
    echo "  Nextcloud: http://cloud.$DOMAIN"
    echo "  Website:   http://www.$DOMAIN"
    echo ""
    echo "Fuer SSL mit einer echten Domain spaeter erneut ausfuehren:"
    echo "  ./setup.sh --headless --install=core,nextcloud,website --domain=eure-domain.de"
else
    echo ""
    echo "Deine Dienste sind erreichbar unter:"
    echo "  Nextcloud: https://cloud.$DOMAIN"
    echo "  Website:   https://www.$DOMAIN"
fi
echo "========================================="
