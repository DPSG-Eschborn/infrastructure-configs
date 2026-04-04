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
# ║              HILFSFUNKTIONEN                       ║
# ╚═══════════════════════════════════════════════════╝

# Sonderzeichen fuer sed-Ersetzungen escapen
# Verhindert dass /, & oder \ in Werten den sed-Parser brechen
escape_sed() {
    printf '%s' "$1" | sed 's/[&/\\]/\\&/g'
}

# Externe Festplatte erkennen, formatieren und mounten
# Gibt 0 zurueck wenn erfolgreich, 1 wenn uebersprungen/fehlgeschlagen
configure_external_disk() {
    echo ""
    echo "============================================"
    echo "   Externe Festplatte fuer Nextcloud"
    echo "============================================"
    echo ""
    echo "[-] Suche nach verfuegbaren Festplatten..."

    # System-Disk ermitteln (die Festplatte auf der / liegt)
    local root_source
    root_source=$(findmnt -n -o SOURCE / 2>/dev/null || echo "")
    # Device-Name ohne Partitionsnummer (z.B. /dev/sda1 -> /dev/sda)
    local root_disk
    root_disk=$(echo "$root_source" | sed 's/[0-9]*$//' | sed 's/p[0-9]*$//')

    # Alle Block-Devices sammeln (ohne Loops, ROM, System-Disk)
    local disk_devs=()
    local disk_labels=()
    while IFS= read -r line; do
        local dev size
        dev=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')

        # System-Disk ueberspringen
        [[ "$dev" == "$root_disk" ]] && continue

        disk_devs+=("$dev")
        disk_labels+=("$dev  ($size)")
    done < <(lsblk -dpno NAME,SIZE 2>/dev/null | grep -v "loop\|sr\|rom\|zram")

    if [ ${#disk_devs[@]} -eq 0 ]; then
        echo ""
        echo "    Keine externen Festplatten gefunden."
        echo "    Nextcloud nutzt den Standard-Speicher (Server-Festplatte)."
        return 1
    fi

    echo ""
    echo "    Verfuegbare Festplatten:"
    local i
    for i in "${!disk_labels[@]}"; do
        echo "    [$((i+1))] ${disk_labels[$i]}"
    done
    echo ""
    echo "    [0] Keine — Standard-Speicher verwenden"
    echo ""
    read -p "Auswahl: " disk_choice

    if [ -z "$disk_choice" ] || [ "$disk_choice" = "0" ]; then
        return 1
    fi

    local idx=$((disk_choice - 1))
    if [ "$idx" -lt 0 ] || [ "$idx" -ge ${#disk_devs[@]} ]; then
        echo "[!] Ungueltige Auswahl."
        return 1
    fi

    local selected_dev="${disk_devs[$idx]}"
    local mount_point="/mnt/nextcloud-data"

    # Erste Partition finden (oder Device selbst verwenden wenn keine Partitionen)
    local part_dev="$selected_dev"
    local first_part
    first_part=$(lsblk -lnpo NAME,TYPE "$selected_dev" 2>/dev/null | awk '$2 == "part" {print $1; exit}')
    if [ -n "$first_part" ]; then
        part_dev="$first_part"
    fi

    # Dateisystem pruefen
    local fs_type
    fs_type=$(lsblk -no FSTYPE "$part_dev" 2>/dev/null | head -1 | tr -d ' ')

    if [ -z "$fs_type" ]; then
        echo ""
        echo "[!] $part_dev hat KEIN Dateisystem."
        echo "    Die Festplatte muss formatiert werden."
        echo ""
        read -p "    Als ext4 formatieren? (ALLE DATEN GEHEN VERLOREN!) (y/n): " fmt_choice
        if [[ "$fmt_choice" =~ ^[yYjJ] ]]; then
            echo "    Formatiere $part_dev als ext4..."
            mkfs.ext4 -F "$part_dev"
            echo "    -> Formatierung abgeschlossen."
        else
            echo "    Abgebrochen."
            return 1
        fi
    else
        echo "    -> Dateisystem erkannt: $fs_type"
    fi

    # Mount-Punkt erstellen
    mkdir -p "$mount_point"

    # fstab-Eintrag (idempotent: nur hinzufuegen wenn noch keiner existiert)
    if ! grep -q " ${mount_point} " /etc/fstab 2>/dev/null; then
        local disk_uuid
        disk_uuid=$(blkid -s UUID -o value "$part_dev" 2>/dev/null || echo "")
        if [ -n "$disk_uuid" ]; then
            echo "UUID=$disk_uuid $mount_point auto defaults,nofail 0 2" >> /etc/fstab
            echo "    -> fstab-Eintrag hinzugefuegt (UUID=$disk_uuid)."
        else
            echo "$part_dev $mount_point auto defaults,nofail 0 2" >> /etc/fstab
            echo "    -> fstab-Eintrag hinzugefuegt ($part_dev)."
        fi
    else
        echo "    -> fstab-Eintrag existiert bereits."
    fi

    # Mounten (falls noch nicht)
    if ! mountpoint -q "$mount_point" 2>/dev/null; then
        if mount "$mount_point"; then
            echo "    -> Festplatte gemountet."
        else
            echo "[!] WARNUNG: Mount fehlgeschlagen. Prüfe die Festplatte."
            return 1
        fi
    else
        echo "    -> Bereits gemountet."
    fi

    # Berechtigungen fuer Nextcloud (www-data: uid=33, gid=33)
    chown 33:33 "$mount_point"
    chmod 770 "$mount_point"

    echo ""
    echo "[OK] Festplatte konfiguriert:"
    echo "     Device:     $part_dev"
    echo "     Mount:      $mount_point"
    echo "     Nextcloud nutzt diese Festplatte als Datenspeicher."

    CUSTOM_DATA_DIR="$mount_point"
    return 0
}

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
# ║       1. SYSTEMVORAUSSETZUNGEN                     ║
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
# ║       2. PLUGIN-SYSTEM (AUTO-ERKENNUNG)            ║
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
# ║       3. INTERAKTIVES MENU                         ║
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

    # Pruefen welche Module ausgewaehlt sind
    _has_nextcloud=false
    _has_storagebox=false
    for _mod in "${INSTALL_MODULES[@]+${INSTALL_MODULES[@]}}"; do
        [ "$_mod" = "nextcloud" ] && _has_nextcloud=true
        [ "$_mod" = "storagebox" ] && _has_storagebox=true
    done

    # StorageBox ohne Nextcloud ergibt keinen Sinn
    if [ "$_has_storagebox" = true ] && [ "$_has_nextcloud" = false ]; then
        echo ""
        echo "[!] WARNUNG: Storage Box ohne Nextcloud hat keinen Effekt."
        echo "    Die Storage Box wird nur als Nextcloud-Datenspeicher genutzt."
        echo "    Storage Box wird aus der Auswahl entfernt."
        _filtered=()
        for _m in "${INSTALL_MODULES[@]}"; do
            [[ "$_m" != "storagebox" ]] && _filtered+=("$_m")
        done
        INSTALL_MODULES=("${_filtered[@]}")
        _has_storagebox=false
    fi

    # Storage Box Konfigurationsdialog
    if [ "$_has_storagebox" = true ]; then
        echo ""
        echo "============================================"
        echo "   Hetzner Storage Box Konfiguration"
        echo "============================================"
        echo ""
        echo "WICHTIG: Stelle sicher, dass SMB-Support in der Hetzner Console"
        echo "aktiviert ist, bevor du fortfaehrst!"
        echo "(Hetzner Console -> Storage Box -> Einstellungen -> Samba aktivieren)"
        echo ""
        read -p "Dein Storage Box Username (z.B. u123456): " STORAGEBOX_USER
        read -s -p "Dein Storage Box Passwort: " STORAGEBOX_PASS
        echo ""

        if [ -z "$STORAGEBOX_USER" ] || [ -z "$STORAGEBOX_PASS" ]; then
            echo "[!] Kein Username oder Passwort eingegeben. Storage Box wird uebersprungen."
            _filtered=()
            for _m in "${INSTALL_MODULES[@]}"; do
                [[ "$_m" != "storagebox" ]] && _filtered+=("$_m")
            done
            INSTALL_MODULES=("${_filtered[@]}")
            _has_storagebox=false
        else
            echo "[OK] Storage Box Zugangsdaten erfasst."
            CUSTOM_DATA_DIR="/mnt/storagebox-data"
        fi
    fi

    # Externe Festplatte Dialog (nur wenn Nextcloud OHNE StorageBox/Custom-Dir)
    if [ "$_has_nextcloud" = true ] && [ "$_has_storagebox" = false ] && [ -z "$CUSTOM_DATA_DIR" ]; then
        echo ""
        read -p "Moechtest du eine externe Festplatte fuer Nextcloud nutzen? (y/n): " _disk_choice
        if [[ "$_disk_choice" =~ ^[yYjJ] ]]; then
            configure_external_disk || true
        fi
    fi
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
# ║       5. DOCKER NETZWERK                           ║
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
# ║       6. DEPLOYMENT                                ║
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

        # .env Konfiguration generieren (Atomic Write Pattern)
        if [ ! -f "$ENV_FILE" ]; then
            if [ -f "$MOD_PATH/.env.example" ]; then
                TMP_ENV="$MOD_PATH/.env.tmp"
                cp "$MOD_PATH/.env.example" "$TMP_ENV"

                # Platzhalter ersetzen (escape_sed schuetzt Sonderzeichen)
                sed -i "s/DOMAIN_PLACEHOLDER/$(escape_sed "$DOMAIN")/g" "$TMP_ENV"

                if [ -n "$STORAGEBOX_USER" ]; then
                    sed -i "s/STORAGEBOX_PLACEHOLDER/$(escape_sed "$STORAGEBOX_USER")/g" "$TMP_ENV"
                fi
                if [ -n "$STORAGEBOX_PASS" ]; then
                    sed -i "s/STORAGEBOXPW_PLACEHOLDER/$(escape_sed "$STORAGEBOX_PASS")/g" "$TMP_ENV"
                fi

                # Zufaellige Passwoerter generieren (hex = nur [0-9a-f], kein Escaping noetig)
                while grep -q 'PASSWORD_PLACEHOLDER' "$TMP_ENV"; do
                    RANDOM_PW=$(openssl rand -hex 16)
                    sed -i "0,/PASSWORD_PLACEHOLDER/s/PASSWORD_PLACEHOLDER/$RANDOM_PW/" "$TMP_ENV"
                done

                # Nextcloud: Custom Data-Dir anwenden (StorageBox, ext. Festplatte, --data-dir)
                if [ "$mod" = "nextcloud" ] && [ -n "$CUSTOM_DATA_DIR" ]; then
                    sed -i "s|^NEXTCLOUD_DATA_DIR=.*|NEXTCLOUD_DATA_DIR=$(escape_sed "$CUSTOM_DATA_DIR")|" "$TMP_ENV"
                    echo "    -> Data-Directory: $CUSTOM_DATA_DIR"
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

        # Modul-Typ-Erkennung: mount.sh (Host-Level) vs docker-compose.yml (Container)
        if [ -f "$MOD_PATH/mount.sh" ]; then
            echo "    -> Fuehre Host-Level Setup aus..."
            chmod +x "$MOD_PATH/mount.sh"
            bash "$MOD_PATH/mount.sh"
        elif [ -f "$MOD_PATH/docker-compose.yml" ]; then
            echo "    -> Starte Container..."
            cd "$MOD_PATH"
            docker compose up -d | sed 's/^/       /'
            cd - > /dev/null
        else
            echo "    [!] WARNUNG: Weder mount.sh noch docker-compose.yml gefunden."
        fi
    else
        echo "[!] WARNUNG: Das angeforderte Modul '$mod' existiert nicht. Ignoriere."
    fi
done

# ╔═══════════════════════════════════════════════════╗
# ║       7. ERGEBNIS                                  ║
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
