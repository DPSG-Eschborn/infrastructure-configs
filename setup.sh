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
# Credentials koennen als Environment-Variablen uebergeben werden
# (bevorzugt gegenueber CLI-Argumenten, da nicht in Prozessliste sichtbar)
STORAGEBOX_USER="${STORAGEBOX_USER:-}"
STORAGEBOX_PASS="${STORAGEBOX_PASS:-}"
CUSTOM_DATA_DIR="${CUSTOM_DATA_DIR:-}"

# ╔═══════════════════════════════════════════════════╗
# ║              HILFSFUNKTIONEN                      ║
# ╚═══════════════════════════════════════════════════╝

# Sonderzeichen fuer sed-Ersetzungen escapen
# Verhindert dass /, & oder \ in Werten den sed-Parser brechen
escape_sed() {
    printf '%s' "$1" | sed 's/[&/\\]/\\&/g'
}

# External disk logic moved to extensions/nextcloud/configure.sh

# ╔═══════════════════════════════════════════════════╗
# ║              PARAMETER VERARBEITEN                ║
# ╚═══════════════════════════════════════════════════╝

for arg in "$@"; do
    case $arg in
        --interactive) MODE="interactive" ;;
        --headless) MODE="headless" ;;
        --install=*)
            IFS=',' read -ra ADDR <<< "${arg#*=}"
            for i in "${ADDR[@]}"; do
                INSTALL_MODULES+=("$i")
            done
            ;;
        --domain=*) DOMAIN="${arg#*=}" ;;
        --storagebox-user=*) STORAGEBOX_USER="${arg#*=}" ;;
        --storagebox-pass=*) STORAGEBOX_PASS="${arg#*=}" ;;
        --data-dir=*) CUSTOM_DATA_DIR="${arg#*=}" ;;
    esac
done

echo "========================================="
echo "   Pfadfinder Cloud Setup-Engine"
echo "========================================="
echo "Modus: $MODE"

# ╔═══════════════════════════════════════════════════╗
# ║       1. SYSTEMVORAUSSETZUNGEN                    ║
# ╚═══════════════════════════════════════════════════╝

# 1a. Docker installieren (Idempotent)
if ! command -v docker &> /dev/null; then
    echo "[+] Docker nicht gefunden. Installiere offizielles Docker-Engine..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    echo "[+] Docker wurde erfolgreich installiert."
else
    echo "[OK] Docker ist bereits installiert."
fi

# 1b. Server-Haertung (Idempotent)
echo ""
echo "[-] Pruefe Sicherheitskonfiguration..."

# fail2ban: Schuetzt SSH vor Brute-Force-Angriffen
if ! command -v fail2ban-client &> /dev/null; then
    echo "[+] Installiere fail2ban (SSH Brute-Force-Schutz)..."
    DEBIAN_FRONTEND=noninteractive apt-get install -yqq fail2ban >/dev/null
    systemctl enable fail2ban >/dev/null 2>&1
    systemctl start fail2ban >/dev/null 2>&1
    echo "    -> fail2ban installiert und aktiviert."
else
    echo "[OK] fail2ban bereits installiert."
fi

# unattended-upgrades: Automatische Sicherheitspatches
if ! dpkg -s unattended-upgrades &>/dev/null; then
    echo "[+] Installiere automatische Sicherheitsupdates..."
    DEBIAN_FRONTEND=noninteractive apt-get install -yqq unattended-upgrades >/dev/null
    echo 'APT::Periodic::Update-Package-Lists "1";' > /etc/apt/apt.conf.d/20auto-upgrades
    echo 'APT::Periodic::Unattended-Upgrade "1";' >> /etc/apt/apt.conf.d/20auto-upgrades
    echo "    -> Automatische Sicherheitsupdates aktiviert."
else
    echo "[OK] Automatische Sicherheitsupdates bereits konfiguriert."
fi

# UFW Firewall: deny-all + Whitelist
if command -v ufw &> /dev/null; then
    if ! ufw status | grep -q "Status: active"; then
        echo "[+] Aktiviere UFW Firewall..."
        ufw default deny incoming >/dev/null 2>&1
        ufw default allow outgoing >/dev/null 2>&1
        ufw allow 22/tcp >/dev/null 2>&1
        ufw allow 80/tcp >/dev/null 2>&1
        ufw allow 443/tcp >/dev/null 2>&1
        ufw --force enable >/dev/null 2>&1
        echo "    -> Firewall aktiv: Nur SSH (22), HTTP (80), HTTPS (443) erlaubt."
    else
        echo "[OK] UFW Firewall bereits aktiv."
    fi
else
    echo "[+] Installiere UFW Firewall..."
    DEBIAN_FRONTEND=noninteractive apt-get install -yqq ufw >/dev/null
    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1
    ufw allow 22/tcp >/dev/null 2>&1
    ufw allow 80/tcp >/dev/null 2>&1
    ufw allow 443/tcp >/dev/null 2>&1
    ufw --force enable >/dev/null 2>&1
    echo "    -> UFW installiert und aktiviert."
fi

# ╔═══════════════════════════════════════════════════╗
# ║       2. PLUGIN-SYSTEM (AUTO-ERKENNUNG)           ║
# ╚═══════════════════════════════════════════════════╝

declare -A PLUGINS_NAME
declare -A PLUGINS_DESC
declare -A PLUGINS_PATH
AVAILABLE_MODULES=()

echo ""
echo "[-] Scanne nach Modulen in /core/ und /extensions/..."

shopt -s nullglob
for manifest in ./core/*/manifest.env ./extensions/*/manifest.env; do
    if [ -f "$manifest" ]; then
        source "$manifest"
        PLUGINS_NAME[$MODULE_ID]="$MODULE_NAME"
        PLUGINS_DESC[$MODULE_ID]="$MODULE_DESCRIPTION"
        PLUGINS_PATH[$MODULE_ID]="$(dirname "$manifest")"
        AVAILABLE_MODULES+=("$MODULE_ID")
        echo "    -> Gefunden: $MODULE_NAME ($MODULE_ID) - $MODULE_DESCRIPTION"
    fi
done
shopt -u nullglob

# ╔═══════════════════════════════════════════════════╗
# ║       3. INTERAKTIVES MENU                        ║
# ╚═══════════════════════════════════════════════════╝

if [ "$MODE" = "interactive" ]; then
    echo ""
    read -p "Welche Basis-Domain moechtest du konfigurieren? (leer = Test-Modus): " DOMAIN_INPUT
    if [ -n "$DOMAIN_INPUT" ]; then
        DOMAIN="$DOMAIN_INPUT"
    fi

    echo ""
    echo "--- Modul Aktivierung ---"
    for mod in "${AVAILABLE_MODULES[@]}"; do
        read -p "[?] Installiere ${PLUGINS_NAME[$mod]}? (y/n): " choice
        case "$choice" in
          y|Y ) INSTALL_MODULES+=("$mod");;
          * ) echo "    Ueberspringe $mod.";;
        esac
    done

    # Setup-API fuer validate.sh exportieren
    ACTIVE_MODULES="${INSTALL_MODULES[*]}"
    export ACTIVE_MODULES

    # --- Phase 2: VALIDATE ---
    # Entfernt Module, die ihre Abhaengigkeiten nicht erfuellen (z.B. StorageBox ohne Nextcloud)
    VALIDATED_MODULES=()
    for mod in "${INSTALL_MODULES[@]}"; do
        if [[ -n "${PLUGINS_PATH[$mod]:-}" ]]; then
            MOD_PATH="${PLUGINS_PATH[$mod]}"
            if [ -f "$MOD_PATH/validate.sh" ]; then
                if ! bash "$MOD_PATH/validate.sh"; then
                    continue # Modul wird uebersprungen/entfernt
                fi
            fi
        fi
        VALIDATED_MODULES+=("$mod")
    done
    INSTALL_MODULES=("${VALIDATED_MODULES[@]}")
    
    # ACTIVE_MODULES nach Validation updaten
    ACTIVE_MODULES="${INSTALL_MODULES[*]}"
    export ACTIVE_MODULES

    # --- Phase 3: CONFIGURE ---
    # Führt interaktive Abfragen (z.B. Credentials, Festplatte) auf Basis der aktivierten Module aus
    export ASSISTANT_MODE="$MODE"
    # Wenn von außen z.B. per CLI Argument gesetzt, exportieren wir das für configure.sh
    export CUSTOM_DATA_DIR="${CUSTOM_DATA_DIR:-}"
    export SYSTEM_DOMAIN="$DOMAIN"

    for mod in "${INSTALL_MODULES[@]}"; do
        MOD_PATH="${PLUGINS_PATH[$mod]}"
        if [ -f "$MOD_PATH/configure.sh" ]; then
            MODULE_ENV_FILE="$MOD_PATH/.env.configure"
            export MODULE_ENV_FILE
            
            # configure.sh kann Variablen setzen (z.B. CUSTOM_DATA_DIR, STORAGEBOX_USER)
            # indem sie IN die Datei $MODULE_ENV_FILE geschrieben werden.
            bash "$MOD_PATH/configure.sh"
            
            if [ -f "$MODULE_ENV_FILE" ]; then
                # Ergebnisse als Shell-Variablen in setup.sh importieren
                # Hierdurch wird z.B. CUSTOM_DATA_DIR direkt in der setup.sh Laufzeit aktualisiert
                source "$MODULE_ENV_FILE"
                rm -f "$MODULE_ENV_FILE"
            fi
        fi
    done
fi

# ╔═══════════════════════════════════════════════════╗
# ║       4. DOMAIN-KONFIGURATION                     ║
# ╚═══════════════════════════════════════════════════╝

if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "AUTO" ]; then
    echo "[-] Kein Domainname uebergeben. Erstelle automatische .nip.io Test-Domain..."
    PUBLIC_IP=$(curl -4 -s -m 10 icanhazip.com)
    if [ -n "$PUBLIC_IP" ]; then
        DOMAIN="${PUBLIC_IP}.nip.io"
        echo "    -> Dynamische Domain generiert: $DOMAIN"
    else
        echo "[!] FEHLER: Konnte Server IP nicht ermitteln. Abbruch."
        exit 1
    fi
fi

# Test-Modus Erkennung: .nip.io Domains koennen kein SSL bekommen
TEST_MODE=false
if [[ "$DOMAIN" == *.nip.io ]]; then
    TEST_MODE=true
    echo ""
    echo "============================================"
    echo "[!] TEST-MODUS AKTIV"
    echo "[!] .nip.io Domain erkannt - HTTPS wird deaktiviert."
    echo "[!] SSL-Zertifikate sind nur mit einer echten Domain moeglich."
    echo "[!] Alle Dienste werden ueber HTTP erreichbar sein."
    echo "============================================"
fi

# Headless: StorageBox Data-Dir setzen (wenn Credentials vorhanden aber CUSTOM_DATA_DIR leer)
if [ -n "$STORAGEBOX_USER" ] && [ -n "$STORAGEBOX_PASS" ] && [ -z "$CUSTOM_DATA_DIR" ]; then
    CUSTOM_DATA_DIR="/mnt/storagebox-data"
fi

# ╔═══════════════════════════════════════════════════╗
# ║       5. DOCKER NETZWERK                          ║
# ╚═══════════════════════════════════════════════════╝

echo ""
echo "[-] Pruefe Docker-Netzwerk..."
if ! docker network ls | grep -q "pfadfinder_net"; then
    docker network create pfadfinder_net
    echo "    -> Netzwerk 'pfadfinder_net' erstellt."
else
    echo "    -> Netzwerk existiert bereits."
fi

# ╔═══════════════════════════════════════════════════╗
# ║       6. DEPLOYMENT                               ║
# ╚═══════════════════════════════════════════════════╝

echo ""
# nounset-sichere Pruefung: ${array[*]:+set} expandiert nur wenn Array nicht leer
if [ "${INSTALL_MODULES[*]:+set}" = "set" ]; then
    echo "Starte Deployment Prozess fuer: ${INSTALL_MODULES[*]}"
else
    echo "Keine Module zum Installieren ausgewaehlt."
fi

for mod in "${INSTALL_MODULES[@]+${INSTALL_MODULES[@]}}"; do
    # Existiert das Modul in unseren ausgelesenen Plugins?
    if [[ -n "${PLUGINS_PATH[$mod]:-}" ]]; then
        MOD_PATH="${PLUGINS_PATH[$mod]}"
        echo "========================================="
        echo "[+] Aktiviere Modul: ${PLUGINS_NAME[$mod]}"

        ENV_FILE="$MOD_PATH/.env"

        # --- Phase 4: ENV GENERATION ---
        # .env Konfiguration generieren (Atomic Write Pattern)
        if [ ! -f "$ENV_FILE" ]; then
            if [ -f "$MOD_PATH/.env.example" ]; then
                TMP_ENV="$MOD_PATH/.env.tmp"
                cp "$MOD_PATH/.env.example" "$TMP_ENV"

                # Standard Platzhalter einlesen: Domain
                sed -i "s/DOMAIN_PLACEHOLDER/$(escape_sed "$DOMAIN")/g" "$TMP_ENV"

                # Generische Legacy Variablen (falls noch im Environment vorhanden z.B. bei Cloud-Init)
                if [ -n "${STORAGEBOX_USER:-}" ]; then
                    sed -i "s/STORAGEBOX_PLACEHOLDER/$(escape_sed "$STORAGEBOX_USER")/g" "$TMP_ENV"
                fi
                if [ -n "${STORAGEBOX_PASS:-}" ]; then
                    sed -i "s/STORAGEBOXPW_PLACEHOLDER/$(escape_sed "$STORAGEBOX_PASS")/g" "$TMP_ENV"
                fi

                # Zufaellige Passwoerter generieren (hex = nur [0-9a-f], kein Escaping noetig)
                while grep -q 'PASSWORD_PLACEHOLDER' "$TMP_ENV"; do
                    RANDOM_PW=$(openssl rand -hex 16)
                    sed -i "0,/PASSWORD_PLACEHOLDER/s/PASSWORD_PLACEHOLDER/$RANDOM_PW/" "$TMP_ENV"
                done

                # Genereller Data-Dir Setter: Module koennen NEXTCLOUD_DATA_DIR als Variable lassen
                if [ -n "$CUSTOM_DATA_DIR" ]; then
                    sed -i "s|^NEXTCLOUD_DATA_DIR=.*|NEXTCLOUD_DATA_DIR=$(escape_sed "$CUSTOM_DATA_DIR")|" "$TMP_ENV"
                    # Log nur bei NEXTCLOUD, falls er hier eingreift
                    if [ "$mod" = "nextcloud" ]; then
                         echo "    -> Data-Directory: $CUSTOM_DATA_DIR"
                    fi
                fi

                # Atomares Verschieben
                mv "$TMP_ENV" "$ENV_FILE"
                echo "    -> Konfiguration (.env) dynamisch generiert."
            fi
        else
            echo "    -> Modul bereits konfiguriert (.env existiert). Ueberspringe Generierung."
            # Bei Re-Run: Data-Dir trotzdem aktualisieren wenn noetig
            if [ "$mod" = "nextcloud" ] && [ -n "$CUSTOM_DATA_DIR" ]; then
                if grep -q '^NEXTCLOUD_DATA_DIR=' "$ENV_FILE"; then
                    sed -i "s|^NEXTCLOUD_DATA_DIR=.*|NEXTCLOUD_DATA_DIR=$(escape_sed "$CUSTOM_DATA_DIR")|" "$ENV_FILE"
                    echo "    -> Data-Directory aktualisiert: $CUSTOM_DATA_DIR"
                fi
            fi
        fi

        # Compose-Datei: Original wiederherstellen falls Backup vorhanden
        if [ -f "$MOD_PATH/docker-compose.yml.original" ]; then
            cp "$MOD_PATH/docker-compose.yml.original" "$MOD_PATH/docker-compose.yml"
        fi

        # Test-Modus: Compose-Dateien fuer HTTP-Betrieb anpassen
        if [ "$TEST_MODE" = true ] && [ -f "$MOD_PATH/docker-compose.yml" ]; then
            if [ ! -f "$MOD_PATH/docker-compose.yml.original" ]; then
                cp "$MOD_PATH/docker-compose.yml" "$MOD_PATH/docker-compose.yml.original"
            fi
            echo "    -> Test-Modus: Passe auf HTTP-Betrieb an..."
            if [ "$mod" = "core" ]; then
                sed -i '/redirections/d' "$MOD_PATH/docker-compose.yml"
            else
                sed -i 's/entrypoints=websecure/entrypoints=web/g' "$MOD_PATH/docker-compose.yml"
                sed -i '/certresolver/d' "$MOD_PATH/docker-compose.yml"
            fi
        fi

        # --- Phase 5: PRE-DEPLOY ---
        # Host-Level Setup VOR dem Container-Start
        if [ -f "$MOD_PATH/pre-deploy.sh" ]; then
            echo "    -> Fuehre pre-deploy.sh aus..."
            chmod +x "$MOD_PATH/pre-deploy.sh"
            bash "$MOD_PATH/pre-deploy.sh"
        elif [ -f "$MOD_PATH/mount.sh" ]; then
            echo "    -> Fuehre mount.sh aus (Legacy)..."
            chmod +x "$MOD_PATH/mount.sh"
            bash "$MOD_PATH/mount.sh"
        fi

        # --- Phase 6: DEPLOY ---
        if [ -f "$MOD_PATH/docker-compose.yml" ]; then
            echo "    -> Starte Container..."
            cd "$MOD_PATH"
            docker compose up -d | sed 's/^/       /'
            cd - > /dev/null
        fi

        # --- Phase 7: POST-DEPLOY ---
        if [ -f "$MOD_PATH/post-deploy.sh" ]; then
            echo "    -> Fuehre post-deploy.sh aus..."
            chmod +x "$MOD_PATH/post-deploy.sh"
            bash "$MOD_PATH/post-deploy.sh"
        fi
    else
        echo "[!] WARNUNG: Das angeforderte Modul '$mod' existiert nicht. Ignoriere."
    fi
done

# ╔═══════════════════════════════════════════════════╗
# ║       7. ERGEBNIS                                 ║
# ╚═══════════════════════════════════════════════════╝

echo ""
echo "========================================="
echo "Setup abgeschlossen!"
echo "Basis-Domain: $DOMAIN"
if [ -n "$CUSTOM_DATA_DIR" ]; then
    echo "Datenspeicher: $CUSTOM_DATA_DIR"
fi
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
