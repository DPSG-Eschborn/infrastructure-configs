#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Pfadfinder-Cloud Setup-Assistent (Linux/macOS)
#
# Provider-agnostischer Setup-Wizard fuer die Pfadfinder-Cloud Infrastruktur.
# Unterstuetzte Provider: Hetzner Cloud (API), Remote-Server (SSH), Lokal.
#
# Ausfuehrung: chmod +x deploy.sh && ./deploy.sh
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
set -euo pipefail

# Bash 4.0+ Voraussetzung (fuer assoziative Arrays, Regex =~, etc.)
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "[!] FEHLER: Bash 4.0+ wird benoetigt (installiert: ${BASH_VERSION})"
    echo ""
    echo "    macOS: brew install bash"
    echo "    Linux: sudo apt-get install bash"
    exit 1
fi

# ╔════════════════════════════════════════════════════════════════════╗
# ║                        KONFIGURATION                              ║
# ╚════════════════════════════════════════════════════════════════════╝

readonly REPO_URL="https://github.com/DPSG-Eschborn/infrastructure-configs.git"
readonly BOOTSTRAP_URL="https://raw.githubusercontent.com/DPSG-Eschborn/infrastructure-configs/main/bootstrap.sh"
readonly HETZNER_API="https://api.hetzner.cloud/v1"
readonly SERVER_TYPE="cx22"
readonly SERVER_IMAGE="ubuntu-24.04"
readonly SERVER_LOCATION="fsn1"

# Laufzeit-Zustand (wird von den Wizard-Funktionen gesetzt)
PROVIDER_TYPE=""
PROVIDER_NAME=""
HETZNER_TOKEN=""
GITHUB_USER=""
SSH_IP=""
SSH_PORT="22"
DEPLOY_DOMAIN=""
DEPLOY_MODULES=()
DEPLOY_SB_USER=""
DEPLOY_SB_PASS=""
DEPLOY_DATA_DIR=""
RESULT_IP=""
RESULT_ROOT_PW=""

# jq-Verfuegbarkeit (wird fuer Hetzner-API benoetigt)
HAS_JQ=false
command -v jq &>/dev/null && HAS_JQ=true

# ╔════════════════════════════════════════════════════════════════════╗
# ║                       UI-HILFSFUNKTIONEN                           ║
# ╚════════════════════════════════════════════════════════════════════╝

# ANSI Farb-Konstanten (Terminal-unabhaengig)
readonly C_RESET="\033[0m"
readonly C_RED="\033[0;31m"
readonly C_GREEN="\033[0;32m"
readonly C_YELLOW="\033[0;33m"
readonly C_CYAN="\033[0;36m"
readonly C_GRAY="\033[0;90m"

write_color() {
    local text="$1"
    local color="${2:-$C_RESET}"
    printf "${color}%s${C_RESET}\n" "$text"
}

write_banner() {
    local title="$1"; shift
    local line
    line=$(printf '%0.s=' $(seq 1 56))
    echo ""
    write_color "$line" "$C_CYAN"
    write_color "   $title" "$C_CYAN"
    write_color "$line" "$C_CYAN"
    for text in "$@"; do
        echo "  $text"
    done
    write_color "$line" "$C_CYAN"
    echo ""
}

write_step() {
    local current="$1" total="$2" desc="$3"
    echo ""
    write_color "--- Schritt $current/$total : $desc ---" "$C_YELLOW"
    echo ""
}

write_success() { write_color "[OK] $1" "$C_GREEN"; }
write_warn()    { write_color "[!]  $1" "$C_YELLOW"; }
write_err()     { write_color "[X]  $1" "$C_RED"; }
write_info()    { write_color "[-]  $1" "$C_CYAN"; }

# Liest eine Eingabe mit Validierung gegen erlaubte Werte.
# Prompt geht an stderr, Rueckgabe via stdout (fuer $(..)-Capture).
read_validated() {
    local prompt="$1"; shift
    local valid_choices=("$@")
    while true; do
        printf "%s : " "$prompt" >&2
        local val=""
        read -r val
        for choice in "${valid_choices[@]}"; do
            if [ "$val" = "$choice" ]; then
                printf '%s' "$val"
                return
            fi
        done
        write_warn "Ungueltige Eingabe. Erlaubt: $(IFS=', '; echo "${valid_choices[*]}")" >&2
    done
}

# Liest ein Passwort (verdeckte Eingabe).
# Prompt geht an stderr, Rueckgabe via stdout.
read_secure() {
    local prompt="$1"
    printf "%s : " "$prompt" >&2
    local val=""
    read -rs val
    echo "" >&2  # Newline nach verdeckter Eingabe
    printf '%s' "$val"
}

# Ja/Nein Abfrage. Return-Code: 0 = Ja, 1 = Nein.
# Verwendung: if read_yes_no "Frage?" "true"; then ...
read_yes_no() {
    local prompt="$1"
    local default="${2:-true}"
    local hint
    [ "$default" = "true" ] && hint="J/n" || hint="j/N"
    printf "%s (%s): " "$prompt" "$hint"
    local val=""
    read -r val
    if [ -z "$val" ]; then
        [ "$default" = "true" ] && return 0 || return 1
    fi
    [[ "$val" =~ ^[jJyY] ]] && return 0 || return 1
}

# ╔════════════════════════════════════════════════════════════════════╗
# ║                       INPUT-VALIDIERUNG                            ║
# ╚════════════════════════════════════════════════════════════════════╝

validate_ipv4() {
    local ip="$1"
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra octets <<< "$ip"
        for o in "${octets[@]}"; do
            (( o > 255 )) && return 1
        done
        return 0
    fi
    return 1
}

validate_domain() {
    local domain="$1"
    # RFC 1035: Buchstaben, Zahlen, Bindestriche, Punkte, mind. 2-Char TLD
    [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]
}

test_hetzner_token() {
    local token="$1"
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -m 10 \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        "$HETZNER_API/ssh_keys" 2>/dev/null || echo "000")
    [ "$http_code" = "200" ]
}

# ╔════════════════════════════════════════════════════════════════════╗
# ║                    KONFIGURATIONS-SAMMLUNG                         ║
# ╚════════════════════════════════════════════════════════════════════╝

get_provider_choice() {
    write_banner "Pfadfinder-Cloud Setup-Assistent" \
        "" \
        "Willkommen! Dieses Skript richtet euren" \
        "Pfadfinder-Server vollautomatisch ein." \
        "" \
        "[1] Hetzner Cloud" \
        "    (Wir erstellen den Server fuer euch!)" \
        "" \
        "[2] Eigener Server / anderer Anbieter" \
        "    (Ihr habt schon einen Server mit IP)" \
        "" \
        "[3] Dieser Computer hier" \
        "    (Fuer lokale Homeserver / Raspberry Pi)" \
        ""

    local choice
    choice=$(read_validated "Deine Wahl" "1" "2" "3")

    case "$choice" in
        1)
            PROVIDER_TYPE="hetzner"
            PROVIDER_NAME="Hetzner Cloud ($SERVER_TYPE, $SERVER_LOCATION)"
            ;;
        2)
            PROVIDER_TYPE="ssh"
            PROVIDER_NAME="Eigener Server (SSH)"
            ;;
        3)
            PROVIDER_TYPE="local"
            PROVIDER_NAME="Lokale Installation"
            ;;
    esac
}

get_hetzner_config() {
    write_step 1 4 "Hetzner Cloud Zugangsdaten"

    # jq ist Voraussetzung fuer JSON-Parsing der Hetzner API
    if [ "$HAS_JQ" = false ]; then
        write_err "jq wird fuer die Hetzner-API benoetigt, ist aber nicht installiert."
        echo ""
        echo "  Installation:"
        echo "    Ubuntu/Debian: sudo apt-get install jq"
        echo "    macOS:         brew install jq"
        echo "    Fedora:        sudo dnf install jq"
        echo ""
        exit 1
    fi

    echo "  Fuer die automatische Server-Erstellung brauchen wir"
    echo "  deinen Hetzner Cloud API-Token. So bekommst du ihn:"
    echo ""
    echo "    1. Gehe auf https://console.hetzner.cloud"
    echo "    2. Waehle dein Projekt (oder erstelle eins)"
    echo "    3. Klicke links auf 'Sicherheit' > 'API-Tokens'"
    echo "    4. Klicke 'API-Token generieren'"
    echo "    5. Name: 'pfadfinder-setup'"
    echo "       Berechtigung: 'Lesen & Schreiben'"
    echo ""

    while true; do
        HETZNER_TOKEN=$(read_secure "Dein API-Token")
        if [ -z "$HETZNER_TOKEN" ]; then
            write_warn "Kein Token eingegeben."
            continue
        fi
        write_info "Pruefe Token bei Hetzner..."
        if test_hetzner_token "$HETZNER_TOKEN"; then
            write_success "API-Token gueltig!"
            break
        else
            write_err "Token ungueltig oder Hetzner nicht erreichbar. Nochmal versuchen."
        fi
    done

    echo ""
    echo "  Optional: GitHub-Username fuer SSH-Zugang zum Server."
    echo "  (Dein oeffentlicher SSH-Key wird automatisch importiert.)"
    echo "  Leer lassen = nur Root-Passwort Zugang."
    echo ""
    printf "GitHub Username (optional): "
    read -r GITHUB_USER
}

get_ssh_config() {
    write_step 1 4 "Server-Verbindungsdaten"

    if ! command -v ssh &>/dev/null; then
        write_err "SSH-Client nicht gefunden!"
        echo ""
        echo "  Installation:"
        echo "    Ubuntu/Debian: sudo apt-get install openssh-client"
        echo "    macOS:         Bereits vorinstalliert"
        echo ""
        exit 1
    fi

    write_success "SSH-Client gefunden."
    echo ""

    # IP-Adresse
    while true; do
        printf "IP-Adresse deines Servers: "
        read -r SSH_IP
        if validate_ipv4 "$SSH_IP"; then
            break
        fi
        write_warn "Ungueltige IP-Adresse. Format: z.B. 123.45.67.89"
    done

    # SSH-Port (Freitext mit Validierung)
    while true; do
        printf "SSH-Port [22]: "
        local port_input=""
        read -r port_input
        if [ -z "$port_input" ]; then
            SSH_PORT="22"
            break
        fi
        if [[ "$port_input" =~ ^[0-9]{1,5}$ ]]; then
            local port_num=$((port_input))
            if (( port_num >= 1 && port_num <= 65535 )); then
                SSH_PORT="$port_input"
                break
            fi
        fi
        write_warn "Ungueltiger Port. Erlaubt: 1-65535"
    done
}

get_deployment_config() {
    write_step 2 4 "Konfiguration"

    # --- Domain ---
    echo "  Habt ihr schon eine Domain (z.B. dpsg-muster.de)?"
    echo "  Falls nicht, einfach leer lassen - dann nutzen wir"
    echo "  einen Testmodus der auch ohne Domain funktioniert."
    echo "  (Ihr koennt die Domain spaeter jederzeit aendern.)"
    echo ""

    while true; do
        printf "Eure Domain (leer = Testmodus): "
        local domain_input=""
        read -r domain_input
        if [ -z "$domain_input" ]; then
            DEPLOY_DOMAIN="AUTO"
            write_info "Testmodus: Server wird ueber IP erreichbar sein (HTTP)."
            break
        fi
        if validate_domain "$domain_input"; then
            DEPLOY_DOMAIN="$domain_input"
            write_success "Domain: $DEPLOY_DOMAIN"
            break
        fi
        write_warn "Ungueltige Domain. Beispiel: dpsg-muster.de"
    done
    echo ""

    # --- Module ---
    echo "  Welche Dienste sollen installiert werden?"
    echo ""
    DEPLOY_MODULES=("core")
    write_color "  [*] Traefik (Reverse Proxy) - immer aktiv" "$C_GRAY"

    if read_yes_no "  Nextcloud installieren? (empfohlen)" "true"; then
        DEPLOY_MODULES+=("nextcloud")
    fi
    if read_yes_no "  Stammes-Website installieren?" "false"; then
        DEPLOY_MODULES+=("website")
    fi

    # --- Storage Box ---
    local has_nextcloud=false
    for m in "${DEPLOY_MODULES[@]}"; do
        [ "$m" = "nextcloud" ] && has_nextcloud=true
    done

    if [ "$has_nextcloud" = true ]; then
        echo ""
        echo "  Habt ihr eine Hetzner Storage Box als Speicher?"
        echo "  (Guenstiger Massenspeicher fuer Nextcloud-Dateien)"
        echo ""
        if read_yes_no "  Hetzner Storage Box einbinden?" "false"; then
            echo ""
            write_warn "WICHTIG: SMB muss in der Hetzner Console aktiviert sein!"
            echo "  (Hetzner Console > Storage Box > Einstellungen > Samba)"
            echo ""

            while true; do
                printf "  Storage Box Username (z.B. u123456): "
                read -r DEPLOY_SB_USER
                if [[ "$DEPLOY_SB_USER" =~ ^u[0-9]+(-sub[0-9]+)?$ ]]; then
                    break
                fi
                write_warn "Format: u123456 oder u123456-sub1"
            done
            DEPLOY_SB_PASS=$(read_secure "  Storage Box Passwort")

            if [ -n "$DEPLOY_SB_PASS" ]; then
                # StorageBox VOR Nextcloud einfuegen (Mount muss vor Container existieren)
                local new_modules=()
                for m in "${DEPLOY_MODULES[@]}"; do
                    [ "$m" = "nextcloud" ] && new_modules+=("storagebox")
                    new_modules+=("$m")
                done
                DEPLOY_MODULES=("${new_modules[@]}")
                write_success "Storage Box konfiguriert."
            else
                write_warn "Kein Passwort eingegeben. Storage Box wird uebersprungen."
                DEPLOY_SB_USER=""
            fi
        fi
    fi

    # --- Externer Speicher (nur wenn kein StorageBox und Nextcloud aktiv) ---
    if [ -z "$DEPLOY_SB_USER" ] && [ "$has_nextcloud" = true ]; then
        echo ""
        echo "  Nextcloud nutzt standardmaessig die Server-Festplatte."
        echo "  Falls ihr eine externe Festplatte nutzen wollt:"
        echo "  - Lokal: Das Setup erkennt angeschlossene Platten automatisch."
        echo "  - SSH: Gebt den Mount-Pfad an, falls die Platte bereits gemountet ist."
        echo ""
        printf "  Benutzerdefinierter Datenpfad (leer = Standard): "
        local custom_path=""
        read -r custom_path
        if [ -n "$custom_path" ]; then
            DEPLOY_DATA_DIR="$custom_path"
            write_success "Datenpfad: $DEPLOY_DATA_DIR"
        fi
    fi
    echo ""
}

show_summary() {
    local modules_str domain_str sb_str data_str
    modules_str=$(IFS=', '; echo "${DEPLOY_MODULES[*]}")
    [ "$DEPLOY_DOMAIN" = "AUTO" ] && domain_str="Testmodus (IP)" || domain_str="$DEPLOY_DOMAIN"
    [ -n "$DEPLOY_SB_USER" ] && sb_str="$DEPLOY_SB_USER (aktiv)" || sb_str="nicht konfiguriert"

    if [ -n "$DEPLOY_DATA_DIR" ]; then
        data_str="$DEPLOY_DATA_DIR"
    elif [ -n "$DEPLOY_SB_USER" ]; then
        data_str="/mnt/storagebox-data (via StorageBox)"
    else
        data_str="Standard (Server-Festplatte)"
    fi

    write_banner "Zusammenfassung" \
        "" \
        "Provider:      $PROVIDER_NAME" \
        "Domain:        $domain_str" \
        "Module:        $modules_str" \
        "Datenspeicher: $data_str" \
        "Storage Box:   $sb_str" \
        ""
}

# ╔════════════════════════════════════════════════════════════════════╗
# ║                     PROVIDER-IMPLEMENTIERUNGEN                     ║
# ╚════════════════════════════════════════════════════════════════════╝

# Baut die Kommandozeilen-Argumente fuer setup.sh
# Passwoerter werden NICHT als CLI-Argument uebergeben (siehe build_env_prefix)
build_setup_args() {
    local args="--headless"
    args+=" --install=$(IFS=','; echo "${DEPLOY_MODULES[*]}")"
    args+=" --domain=$DEPLOY_DOMAIN"
    if [ -n "$DEPLOY_SB_USER" ]; then
        args+=" --storagebox-user=$DEPLOY_SB_USER"
    fi
    if [ -n "$DEPLOY_DATA_DIR" ]; then
        args+=" --data-dir=$DEPLOY_DATA_DIR"
    fi
    printf '%s' "$args"
}

# Erzeugt Bash-Environment-Prefix fuer sensitive Daten
# Format: STORAGEBOX_PASS='wert' (inline vor dem Befehl)
# Vorteil: Nicht in ps aux sichtbar, nicht im Logfile
build_env_prefix() {
    if [ -n "$DEPLOY_SB_PASS" ]; then
        # Single-Quotes in bash escapen: ' -> '\'' (Quote beenden, escaped Quote, Quote oeffnen)
        local escaped="${DEPLOY_SB_PASS//\'/\'\\\'\'}"
        printf "STORAGEBOX_PASS='%s' " "$escaped"
    fi
}

build_cloud_init_yaml() {
    local setup_args env_prefix ssh_block
    setup_args=$(build_setup_args)
    env_prefix=$(build_env_prefix)

    # SSH-Key Block (optional, abhaengig von GitHub-Username)
    if [ -n "$GITHUB_USER" ]; then
        ssh_block="
  - name: pfadiadmin
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - gh:$GITHUB_USER"
    else
        ssh_block="
  - name: pfadiadmin
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL"
    fi

    # Cloud-Init YAML als Heredoc (identisch mit deploy.ps1 Ausgabe)
    cat <<CLOUD_INIT_EOF
#cloud-config
# Pfadfinder-Cloud: Automatisch generiert von deploy.sh
# Server-Haertung gemaess KDG/DSGVO Anforderungen

# SSH Root-Login deaktivieren (nur Key-Auth fuer pfadiadmin)
ssh_pwauth: false

users:${ssh_block}

package_update: true
package_upgrade: true
packages:
  - git
  - curl
  - openssl
  - fail2ban
  - unattended-upgrades
  - ufw

runcmd:
  # SSH-Haertung: Root-Login verbieten, Max. 3 Versuche
  - sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
  - sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
  - systemctl restart ssh

  # UFW Firewall: deny-all + Whitelist
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow 22/tcp
  - ufw allow 80/tcp
  - ufw allow 443/tcp
  - ufw --force enable

  # Automatische Sicherheitsupdates aktivieren
  - echo 'APT::Periodic::Update-Package-Lists "1";' > /etc/apt/apt.conf.d/20auto-upgrades
  - echo 'APT::Periodic::Unattended-Upgrade "1";' >> /etc/apt/apt.conf.d/20auto-upgrades

  # Pfadfinder-Cloud Setup
  - git clone ${REPO_URL} /opt/pfadfinder-cloud || { echo 'FATAL: git clone fehlgeschlagen' >> /var/log/pfadfinder-setup.log; exit 1; }
  - cd /opt/pfadfinder-cloud && chmod +x setup.sh && ${env_prefix}./setup.sh ${setup_args} > /var/log/pfadfinder-setup.log 2>&1

  # Docker-Gruppe dem Admin-User zuweisen
  - usermod -aG docker pfadiadmin
CLOUD_INIT_EOF
}

invoke_hetzner_deploy() {
    write_step 4 4 "Server erstellen"
    write_info "Generiere Cloud-Init Konfiguration..."

    local cloud_init
    cloud_init=$(build_cloud_init_yaml)

    # JSON-Body mit jq (korrektes Escaping, besonders fuer cloud-init YAML)
    local body
    body=$(jq -n \
        --arg name "pfadfinder-cloud" \
        --arg type "$SERVER_TYPE" \
        --arg image "$SERVER_IMAGE" \
        --arg location "$SERVER_LOCATION" \
        --arg user_data "$cloud_init" \
        '{
            name: $name,
            server_type: $type,
            image: $image,
            location: $location,
            start_after_create: true,
            user_data: $user_data
        }')

    write_info "Erstelle Server bei Hetzner ($SERVER_TYPE in $SERVER_LOCATION)..."

    # API-Aufruf mit HTTP-Status-Trennung
    local response http_code json_body
    response=$(curl -s -w "\n%{http_code}" -m 30 \
        -H "Authorization: Bearer $HETZNER_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$body" \
        "$HETZNER_API/servers" 2>/dev/null) || true

    http_code=$(echo "$response" | tail -1)
    json_body=$(echo "$response" | sed '$d')

    if [ "$http_code" != "201" ]; then
        case "$http_code" in
            422)
                write_err "Server-Name 'pfadfinder-cloud' existiert bereits in diesem Projekt."
                echo "  Loesung: Loesche den alten Server in der Hetzner Console."
                ;;
            403)
                write_err "Keine Berechtigung. Ist der Token auf 'Lesen & Schreiben' gesetzt?"
                ;;
            *)
                write_err "Hetzner API Fehler (HTTP $http_code)"
                echo "$json_body" | head -5 | sed 's/^/  /'
                ;;
        esac
        exit 1
    fi

    RESULT_IP=$(echo "$json_body" | jq -r '.server.public_net.ipv4.ip')
    RESULT_ROOT_PW=$(echo "$json_body" | jq -r '.root_password')
    local server_id
    server_id=$(echo "$json_body" | jq -r '.server.id')

    write_success "Server erstellt! (ID: $server_id)"
    echo ""

    # Polling: Warten bis Server-Status "running" ist
    write_info "Warte bis Server bereit ist..."
    local max_attempts=30
    for ((i = 1; i <= max_attempts; i++)); do
        sleep 5
        local status
        status=$(curl -s -m 10 \
            -H "Authorization: Bearer $HETZNER_TOKEN" \
            "$HETZNER_API/servers/$server_id" 2>/dev/null \
            | jq -r '.server.status' 2>/dev/null) || status="unknown"

        if [ "$status" = "running" ]; then
            write_success "Server laeuft!"
            break
        fi
        echo "  Status: $status ... ($i/$max_attempts)"

        if [ "$i" -eq "$max_attempts" ]; then
            write_warn "Timeout beim Warten. Server wird trotzdem eingerichtet."
        fi
    done
}

invoke_ssh_deploy() {
    write_step 4 4 "Server einrichten"

    local setup_args env_prefix
    setup_args=$(build_setup_args)
    env_prefix=$(build_env_prefix)

    # Remote-Befehl zusammenbauen
    local remote_cmd="curl -sL $BOOTSTRAP_URL -o /tmp/bootstrap.sh && ${env_prefix}bash /tmp/bootstrap.sh $setup_args"

    # Base64-Kodierung um Shell-Escaping-Probleme zu vermeiden
    # (tr -d '\n' fuer macOS-Kompatibilitaet: macOS base64 bricht Zeilen um)
    local b64
    b64=$(printf '%s' "$remote_cmd" | base64 | tr -d '\n')

    write_info "Verbinde mit $SSH_IP (Port $SSH_PORT)..."
    echo ""
    write_warn "Du wirst gleich nach dem Root-Passwort gefragt."
    echo "  (Das ist das Passwort deines Servers, nicht dein lokales Passwort!)"
    echo ""

    write_info "Starte Einrichtung (das dauert 3-5 Minuten)..."
    echo ""

    # SSH-Verbindung — eine einzige Passwort-Eingabe reicht
    local ssh_exit=0
    ssh -o StrictHostKeyChecking=accept-new \
        -o ConnectTimeout=15 \
        -p "$SSH_PORT" \
        "root@$SSH_IP" \
        "echo '$b64' | base64 -d | bash" || ssh_exit=$?

    if [ "$ssh_exit" -ne 0 ]; then
        write_err "SSH-Verbindung fehlgeschlagen (Exit-Code: $ssh_exit)."
        echo ""
        echo "  Moegliche Ursachen:"
        echo "  - IP-Adresse oder Passwort falsch"
        echo "  - Server ist nicht erreichbar (Firewall?)"
        echo "  - SSH-Port stimmt nicht (Standard: 22)"
        exit 1
    fi

    RESULT_IP="$SSH_IP"
}

invoke_local_deploy() {
    write_step 4 4 "Lokale Einrichtung"

    write_info "Pruefe Betriebssystem..."

    if [ ! -f /etc/os-release ]; then
        write_err "Kein Linux-System erkannt."
        echo ""
        echo "  Lokale Installation ist nur auf Linux-Systemen moeglich."
        echo "  Nutze stattdessen:"
        echo "  - Option [1] (Hetzner Cloud) — Server wird automatisch erstellt"
        echo "  - Option [2] (Eigener Server) — SSH-Verbindung zu deinem Linux-Server"
        exit 1
    fi

    local setup_args env_prefix
    setup_args=$(build_setup_args)
    env_prefix=$(build_env_prefix)

    write_info "Starte bootstrap.sh..."

    local cmd="curl -sL $BOOTSTRAP_URL -o /tmp/bootstrap.sh && ${env_prefix}bash /tmp/bootstrap.sh $setup_args"

    # Root-Rechte pruefen: bootstrap.sh/setup.sh benoetigen Root
    if [[ $EUID -ne 0 ]]; then
        write_warn "Root-Rechte benoetigt. Du wirst nach deinem Passwort gefragt."
        sudo bash -c "$cmd"
    else
        bash -c "$cmd"
    fi

    # Oeffentliche IP ermitteln (fuer Ergebnis-Anzeige)
    RESULT_IP=$(curl -4 -s -m 10 icanhazip.com 2>/dev/null || echo "localhost")
}

# ╔════════════════════════════════════════════════════════════════════╗
# ║                       ERGEBNIS-ANZEIGE                             ║
# ╚════════════════════════════════════════════════════════════════════╝

show_result() {
    local is_test_mode=false
    [ "$DEPLOY_DOMAIN" = "AUTO" ] && is_test_mode=true

    local nc_url www_url
    if [ "$is_test_mode" = true ]; then
        nc_url="http://cloud.${RESULT_IP}.nip.io"
        www_url="http://www.${RESULT_IP}.nip.io"
    else
        nc_url="https://cloud.$DEPLOY_DOMAIN"
        www_url="https://www.$DEPLOY_DOMAIN"
    fi

    local lines=()
    lines+=("")
    lines+=("Euer Server wird jetzt eingerichtet!")
    lines+=("(Die Einrichtung dauert ca. 3-5 Minuten.)")
    lines+=("")

    for m in "${DEPLOY_MODULES[@]}"; do
        [ "$m" = "nextcloud" ] && lines+=("Nextcloud: $nc_url")
        [ "$m" = "website" ] && lines+=("Website:   $www_url")
    done

    lines+=("")
    lines+=("Server-IP: $RESULT_IP")

    if [ -n "$RESULT_ROOT_PW" ]; then
        lines+=("")
        lines+=("Root-Passwort: $RESULT_ROOT_PW")
        lines+=("(SICHER AUFBEWAHREN! Wird nur einmal angezeigt!)")
    fi

    if [ "$is_test_mode" = false ]; then
        lines+=("")
        lines+=("WICHTIG: DNS-Eintraege setzen!")
        lines+=("Erstellt bei eurem Domain-Anbieter A-Records:")
        for m in "${DEPLOY_MODULES[@]}"; do
            [ "$m" = "nextcloud" ] && lines+=("  cloud -> $RESULT_IP")
            [ "$m" = "website" ] && lines+=("  www   -> $RESULT_IP")
        done
    fi
    lines+=("")

    write_banner "Fertig!" "${lines[@]}"

    if [ "$PROVIDER_TYPE" = "hetzner" ]; then
        echo ""
        write_color "  Hinweis: Der Server richtet sich im Hintergrund selbst ein." "$C_YELLOW"
        write_color "  Warte ca. 3-5 Minuten, dann sind die Dienste erreichbar." "$C_YELLOW"
        echo ""
    fi
}

# ╔════════════════════════════════════════════════════════════════════╗
# ║                          HAUPTPROGRAMM                            ║
# ╚════════════════════════════════════════════════════════════════════╝

main() {
    # Schritt 1: Provider-Auswahl
    get_provider_choice

    # Provider-spezifische Konfiguration
    case "$PROVIDER_TYPE" in
        hetzner) get_hetzner_config ;;
        ssh)     get_ssh_config ;;
        local)   ;; # Keine zusaetzliche Konfiguration noetig
    esac

    # Schritt 2: Deployment-Konfiguration (provider-agnostisch)
    get_deployment_config

    # Schritt 3: Zusammenfassung + Bestaetigung
    show_summary

    if ! read_yes_no "Alles korrekt? Einrichtung starten?" "true"; then
        write_warn "Abgebrochen."
        exit 0
    fi

    # Schritt 4: Deployment (provider-spezifisch)
    case "$PROVIDER_TYPE" in
        hetzner) invoke_hetzner_deploy ;;
        ssh)     invoke_ssh_deploy ;;
        local)   invoke_local_deploy ;;
    esac

    # Schritt 5: Ergebnis
    show_result
}

# ╔════════════════════════════════════════════════════════════════════╗
# ║                          ENTRY POINT                              ║
# ╚════════════════════════════════════════════════════════════════════╝

# Globaler Error-Handler: Fange unerwartete Fehler ab und zeige hilfreiche Nachricht
trap '
    echo ""
    write_err "Ein Fehler ist aufgetreten."
    echo ""
    echo "  Falls du Hilfe brauchst, oeffne ein Issue auf GitHub:"
    write_color "  $REPO_URL" "$C_CYAN"
    echo ""
    exit 1
' ERR

main
