#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Pfadfinder-Cloud Setup-Assistent (Linux/macOS)
#
# Provider-agnostischer Infrastruktur-Wizard fuer die Pfadfinder-Cloud.
# Erstellt den Server (Hetzner) oder bereitet ihn vor (SSH/Local) und
# oeffnet anschliessend eine SSH-Bridge zum interaktiven Setup-Skript.
#
# Ausfuehrung: chmod +x install.sh && ./install.sh
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
set -euo pipefail

if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
    # Wenn BASH_VERSINFO fehlt (macOS zsh) oder < 4
    if [ -z "${BASH_VERSION:-}" ]; then
        echo "[!] Bitte fuehre das Skript mit 'bash install.sh' aus."
    else
        echo "[!] Deine Bash Version (${BASH_VERSION:-}) ist zu alt. Bitte aktualisiere Bash."
    fi
    exit 1
fi

readonly REPO_URL="https://github.com/DPSG-Eschborn/infrastructure-configs.git"
readonly BOOTSTRAP_URL="https://raw.githubusercontent.com/DPSG-Eschborn/infrastructure-configs/main/engine/bootstrap.sh"
readonly HETZNER_API="https://api.hetzner.cloud/v1"
readonly SERVER_TYPE="cx22"
readonly SERVER_IMAGE="ubuntu-24.04"
readonly SERVER_LOCATION="fsn1"
readonly TEMP_SSH_KEY="/tmp/pfadi_setup_key"

PROVIDER_TYPE=""
PROVIDER_NAME=""
HETZNER_TOKEN=""
GITHUB_USER=""
SSH_IP=""
SSH_PORT="22"
RESULT_IP=""
RESULT_ROOT_PW=""

HAS_JQ=false
command -v jq &>/dev/null && HAS_JQ=true

# ╔════════════════════════════════════════════════════════════════════╗
# ║                       UI-HILFSFUNKTIONEN                           ║
# ╚════════════════════════════════════════════════════════════════════╝

readonly C_RESET="\033[0m"
readonly C_RED="\033[0;31m"
readonly C_GREEN="\033[0;32m"
readonly C_YELLOW="\033[0;33m"
readonly C_CYAN="\033[0;36m"

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

write_step() { write_color "\n--- Schritt $1/$2 : $3 ---" "$C_YELLOW"; echo ""; }
write_success() { write_color "[OK] $1" "$C_GREEN"; }
write_warn()    { write_color "[!]  $1" "$C_YELLOW"; }
write_err()     { write_color "[X]  $1" "$C_RED"; }
write_info()    { write_color "[-]  $1" "$C_CYAN"; }

read_validated() {
    local prompt="$1"; shift
    local valid_choices=("$@")
    while true; do
        printf "%s [%s]: " "$prompt" "${valid_choices[*]}" >&2
        local input=""
        read -r input
        for valid in "${valid_choices[@]}"; do
            if [ "$input" = "$valid" ]; then
                echo "$input"
                return 0
            fi
        done
        write_warn "Ungueltige Eingabe. Bitte waehle aus: ${valid_choices[*]}" >&2
    done
}

read_secure() {
    local prompt="$1"
    local input=""
    printf "%s: " "$prompt" >&2
    stty -echo
    read -r input || true
    stty echo
    echo "" >&2
    echo "$input"
}

read_yes_no() {
    local prompt="$1"
    local default="${2:-true}"
    local default_str="Y/n"
    [ "$default" = "false" ] && default_str="y/N"

    while true; do
        printf "%s [%s]: " "$prompt" "$default_str" >&2
        local choice=""
        read -r choice
        case "${choice,,}" in
            y|yes|j|ja) return 0 ;;
            n|no|nein) return 1 ;;
            "") 
                [ "$default" = "true" ] && return 0 || return 1
                ;;
            *) write_warn "Bitte mit Ja (y) oder Nein (n) antworten." >&2 ;;
        esac
    done
}

validate_ipv4() {
    local ip="$1"
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IFS='.' read -ra octets <<< "$ip"
        for o in "${octets[@]}"; do
            (( o > 255 )) && return 1
        done
        return 0
    fi
    return 1
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
    write_banner "Pfadfinder-Cloud" \
        "" \
        "Dieses Skript bereitet deinen Server vor." \
        "Danach startest du automatisch in das Interaktive Menue." \
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
        1)  PROVIDER_TYPE="hetzner"; PROVIDER_NAME="Hetzner Cloud" ;;
        2)  PROVIDER_TYPE="ssh"; PROVIDER_NAME="Eigener Server" ;;
        3)  PROVIDER_TYPE="local"; PROVIDER_NAME="Lokal" ;;
    esac
}

get_hetzner_config() {
    write_step 1 2 "Hetzner Cloud Zugangsdaten"

    if [ "$HAS_JQ" = false ]; then
        write_err "jq wird fuer die Hetzner-API benoetigt, ist aber nicht installiert."
        exit 1
    fi

    echo "  Gehe auf console.hetzner.cloud > Dein Projekt > Sicherheit > API-Tokens"
    echo "  Generiere ein neues Token mit Berechtigung: 'Lesen & Schreiben'"
    echo ""

    while true; do
        HETZNER_TOKEN=$(read_secure "Dein API-Token")
        if [ -z "$HETZNER_TOKEN" ]; then continue; fi
        write_info "Pruefe Token bei Hetzner..."
        if test_hetzner_token "$HETZNER_TOKEN"; then
            write_success "API-Token gueltig!"
            break
        else
            write_err "Token ungueltig. Nochmal versuchen."
        fi
    done

    echo ""
    echo "  Optional: Dein Github Username (fuer dauerhaften automatischen SSH-Zugriff)"
    printf "GitHub Username: "
    read -r GITHUB_USER
}

get_ssh_config() {
    write_step 1 2 "Server-Verbindungsdaten"

    if ! command -v ssh &>/dev/null; then
        write_err "SSH-Client nicht gefunden!"
        exit 1
    fi

    while true; do
        printf "IP-Adresse deines Servers: "
        read -r SSH_IP
        if validate_ipv4 "$SSH_IP"; then break; fi
        write_warn "Ungueltige IP-Adresse. Format: 123.45.67.89"
    done

    while true; do
        printf "SSH-Port [22]: "
        local port_input=""
        read -r port_input
        if [ -z "$port_input" ]; then
            SSH_PORT="22"
            break
        fi
        if [[ "$port_input" =~ ^[0-9]{1,5}$ ]]; then
            SSH_PORT="$port_input"
            break
        fi
    done
}

# ╔════════════════════════════════════════════════════════════════════╗
# ║                     PROVIDER-IMPLEMENTIERUNGEN                     ║
# ╚════════════════════════════════════════════════════════════════════╝

new_ephemeral_key() {
    write_info "Generiere temporaeren SSH-Schluessel fuer das Setup..."
    rm -f "${TEMP_SSH_KEY}" "${TEMP_SSH_KEY}.pub"
    ssh-keygen -t ed25519 -N "" -C "ephemeral_pfadi_key" -f "${TEMP_SSH_KEY}" -q
}

build_cloud_init_yaml() {
    local pub_key
    pub_key=$(cat "${TEMP_SSH_KEY}.pub")

    local ssh_block
    if [ -n "$GITHUB_USER" ]; then
        ssh_block="
  - name: pfadiadmin
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - gh:$GITHUB_USER
      - $pub_key"
    else
        ssh_block="
  - name: pfadiadmin
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - $pub_key"
    fi

    cat <<CLOUD_INIT_EOF
#cloud-config
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
  # Root Login strikt auf SSH-Keys beschraenken (prohibit-password)
  - sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
  - sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
  - systemctl restart ssh
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow 22/tcp
  - ufw allow 80/tcp
  - ufw allow 443/tcp
  - ufw --force enable
  - echo 'APT::Periodic::Update-Package-Lists "1";' > /etc/apt/apt.conf.d/20auto-upgrades
  - echo 'APT::Periodic::Unattended-Upgrade "1";' >> /etc/apt/apt.conf.d/20auto-upgrades
  # Aktiviere die SSH-Bridge fuer den Installationsvorgang
  - mkdir -p /root/.ssh
  - echo "$pub_key" >> /root/.ssh/authorized_keys
  - chmod 600 /root/.ssh/authorized_keys
CLOUD_INIT_EOF
}

start_ssh_bridge() {
    local ip="$1"
    local port="$2"
    local use_key="${3:-false}"

    write_step 2 2 "SSH-Bridge starten"

    local ssh_cmd="curl -sL $BOOTSTRAP_URL -o /tmp/bootstrap.sh && bash /tmp/bootstrap.sh"

    if [ "$use_key" = true ]; then
        write_info "Warte bis der Server via SSH erreichbar ist (Port $port)..."
        local max_retries=60
        local connected=false
        for ((i = 1; i <= max_retries; i++)); do
            if ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=accept-new -i "$TEMP_SSH_KEY" -p "$port" "root@$ip" "echo 'ready'" &>/dev/null; then
                connected=true
                break
            fi
            sleep 3
        done

        if [ "$connected" = false ]; then
            write_err "Server antwortet nicht. Setup abgebrochen."
            exit 1
        fi

        # Kurz dem Cloud-Init Zeit lassen apt-get zu beenden
        write_info "Server online! Lade interaktives Menue..."
        sleep 5

        write_color "--- Tunnel etabliert. ---" "$C_GREEN"
        # -t erzwingt TTY fuer interaktive bash prompts!
        ssh -t -o StrictHostKeyChecking=accept-new -i "$TEMP_SSH_KEY" -p "$port" "root@$ip" "$ssh_cmd"

        rm -f "${TEMP_SSH_KEY}" "${TEMP_SSH_KEY}.pub"
    else
        write_color "--- Tunnel etabliert. ---" "$C_GREEN"
        write_warn "Du wirst gleich nach deinem Root-Passwort gefragt."
        ssh -t -o StrictHostKeyChecking=accept-new -p "$port" "root@$ip" "$ssh_cmd"
    fi

    echo ""
    write_success "Bridge beendet. Der Server laeuft autark weiter!"
}

invoke_hetzner_deploy() {
    new_ephemeral_key
    local cloud_init
    cloud_init=$(build_cloud_init_yaml)

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
    local response http_code json_body
    response=$(curl -s -w "\n%{http_code}" -m 30 \
        -H "Authorization: Bearer $HETZNER_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$body" \
        "$HETZNER_API/servers" 2>/dev/null) || true

    http_code=$(echo "$response" | tail -1)
    json_body=$(echo "$response" | sed '$d')

    if [ "$http_code" != "201" ]; then
        write_err "Server-Erstellung fehlgeschlagen (HTTP $http_code)"
        echo "$json_body" | head -5 | sed 's/^/  /'
        exit 1
    fi

    RESULT_IP=$(echo "$json_body" | jq -r '.server.public_net.ipv4.ip')
    RESULT_ROOT_PW=$(echo "$json_body" | jq -r '.root_password')

    write_success "Server erstellt! (IP: $RESULT_IP)"
    echo ""
    write_color "Root-Passwort: $RESULT_ROOT_PW" "$C_YELLOW"
    write_info "(SICHER AUFBEWAHREN, WIRD NUR EINMAL ANGEZEIGT!)"
    echo ""

    start_ssh_bridge "$RESULT_IP" "22" true
}

invoke_ssh_deploy() {
    start_ssh_bridge "$SSH_IP" "$SSH_PORT" false
}

invoke_local_deploy() {
    write_step 2 2 "Lokale Einrichtung"
    write_info "Lade setup.sh Umgebung..."
    local cmd="curl -sL $BOOTSTRAP_URL -o /tmp/bootstrap.sh && bash /tmp/bootstrap.sh"

    if [[ $EUID -ne 0 ]]; then
        sudo bash -c "$cmd"
    else
        bash -c "$cmd"
    fi
}

main() {
    get_provider_choice

    case "$PROVIDER_TYPE" in
        hetzner) get_hetzner_config ;;
        ssh)     get_ssh_config ;;
    esac

    echo ""
    write_color "================================================" "$C_CYAN"
    write_color " Server bereit zum Start!" "$C_GREEN"
    write_color "================================================" "$C_CYAN"
    echo ""

    if ! read_yes_no "Infrastruktur aufbauen und Bridge starten?" "true"; then
        exit 0
    fi

    case "$PROVIDER_TYPE" in
        hetzner) invoke_hetzner_deploy ;;
        ssh)     invoke_ssh_deploy ;;
        local)   invoke_local_deploy ;;
    esac
}

trap '
    echo ""
    write_err "Setup unterbrochen / Fehler aufgetreten."
    rm -f "${TEMP_SSH_KEY}" "${TEMP_SSH_KEY}.pub"
    exit 1
' ERR SIGINT

main
