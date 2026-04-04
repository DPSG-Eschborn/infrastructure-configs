#!/bin/bash
# Hetzner Storage Box — CIFS/SMB Mount-Skript
# Referenz: https://docs.hetzner.com/robot/storage-box/access/access-samba-cifs/
#
# Dieses Skript wird von setup.sh aufgerufen (nicht direkt vom User).
# Es erwartet, dass die .env-Datei im selben Verzeichnis bereits generiert wurde.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# .env laden
if [ ! -f "$ENV_FILE" ]; then
    echo "[!] FEHLER: Keine .env Datei gefunden unter $ENV_FILE"
    echo "    Das Skript muss ueber setup.sh aufgerufen werden."
    exit 1
fi

source "$ENV_FILE"

# Variablen validieren
if [ -z "${STORAGEBOX_USER:-}" ] || [ -z "${STORAGEBOX_PASS:-}" ]; then
    echo "[!] FEHLER: STORAGEBOX_USER oder STORAGEBOX_PASS nicht gesetzt."
    exit 1
fi

STORAGEBOX_HOST="${STORAGEBOX_USER}.your-storagebox.de"
MOUNT_POINT="/mnt/storagebox-data"
CREDENTIALS_FILE="/etc/storagebox-credentials.txt"
FSTAB_FILE="/etc/fstab"

echo "    [1/5] Installiere CIFS-Abhaengigkeiten..."
if ! dpkg -s cifs-utils &>/dev/null; then
    DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -yqq cifs-utils >/dev/null
    echo "          cifs-utils installiert."
else
    echo "          cifs-utils bereits vorhanden."
fi

# Kernel-Modul laden (idempotent)
modprobe cifs 2>/dev/null || true

echo "    [2/5] Erstelle Credentials-Datei..."
# Atomic Write: Temporaer schreiben, dann verschieben
TMP_CREDS="${CREDENTIALS_FILE}.tmp"
cat > "$TMP_CREDS" <<EOF
username=${STORAGEBOX_USER}
password=${STORAGEBOX_PASS}
EOF
mv "$TMP_CREDS" "$CREDENTIALS_FILE"
# Hetzner-Doku: chmod 0600 (nur root darf lesen)
chmod 0600 "$CREDENTIALS_FILE"
echo "          Credentials unter $CREDENTIALS_FILE gesichert (chmod 600)."

echo "    [3/5] Erstelle Mount-Verzeichnis..."
if [ ! -d "$MOUNT_POINT" ]; then
    mkdir -p "$MOUNT_POINT"
    echo "          $MOUNT_POINT erstellt."
else
    echo "          $MOUNT_POINT existiert bereits."
fi

echo "    [4/5] Konfiguriere /etc/fstab..."
# Idempotenz: Pruefen ob bereits ein Eintrag fuer diesen Mount-Punkt existiert
# Exakter Match auf den Mount-Punkt (2. Spalte in fstab), um Duplikate zu vermeiden
if grep -q " ${MOUNT_POINT} " "$FSTAB_FILE" 2>/dev/null; then
    echo "          fstab-Eintrag fuer $MOUNT_POINT existiert bereits. Ueberspringe."
else
    # fstab-Eintrag gemaess offizieller Hetzner-Dokumentation:
    # https://docs.hetzner.com/robot/storage-box/access/access-samba-cifs/
    #
    # Optionen:
    #   iocharset=utf8    — Korrekte Zeichenkodierung fuer Dateinamen
    #   rw                — Lese- und Schreibzugriff
    #   seal              — Verschluesseltes SMB (Hetzner-Empfehlung, ab Ubuntu 18.04)
    #   credentials=...   — Passwort-Datei statt Klartext in fstab
    #   uid=33,gid=33     — www-data User/Group (Nextcloud im Docker-Container)
    #   file_mode=0770    — Dateiberechtigungen
    #   dir_mode=0770     — Verzeichnisberechtigungen
    #   nofail            — Server bootet auch wenn Storage Box nicht erreichbar ist
    #   _netdev           — Mount erst nach Netzwerk-Initialisierung
    #
    FSTAB_LINE="//${STORAGEBOX_HOST}/backup ${MOUNT_POINT} cifs iocharset=utf8,rw,seal,credentials=${CREDENTIALS_FILE},uid=33,gid=33,file_mode=0770,dir_mode=0770,nofail,_netdev 0 0"
    
    # Atomic: Eintrag ans Ende von fstab anhaengen
    echo "$FSTAB_LINE" >> "$FSTAB_FILE"
    echo "          fstab-Eintrag hinzugefuegt."
fi

echo "    [5/5] Mounte Storage Box..."
# Pruefen ob bereits gemountet
if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    echo "          $MOUNT_POINT ist bereits gemountet."
else
    if mount "$MOUNT_POINT"; then
        echo "          Storage Box erfolgreich gemountet."
    else
        echo ""
        echo "    [!] WARNUNG: Mount fehlgeschlagen!"
        echo "    Moegliche Ursachen:"
        echo "      1. SMB-Support ist in der Hetzner Console NICHT aktiviert."
        echo "         -> Hetzner Console -> Storage Box -> Einstellungen -> Samba aktivieren"
        echo "      2. Username oder Passwort ist falsch."
        echo "      3. Port 445 wird von einer Firewall blockiert."
        echo ""
        echo "    Der fstab-Eintrag wurde trotzdem angelegt."
        echo "    Nach Behebung des Problems: 'mount ${MOUNT_POINT}' erneut ausfuehren."
        # Kein exit 1 — nofail in fstab sorgt dafuer, dass der Server trotzdem bootet.
        # Das Setup soll weiterlaufen, damit die anderen Module installiert werden.
    fi
fi

# Validierung: Schreibzugriff testen
if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    TEST_FILE="$MOUNT_POINT/.pfadfinder_mount_test"
    if touch "$TEST_FILE" 2>/dev/null && rm -f "$TEST_FILE" 2>/dev/null; then
        echo ""
        echo "    [OK] Storage Box ist gemountet und beschreibbar."
        echo "         Pfad: $MOUNT_POINT"
        echo "         Host: $STORAGEBOX_HOST"
    else
        echo ""
        echo "    [!] WARNUNG: Mount vorhanden, aber Schreibzugriff fehlgeschlagen."
        echo "    Pruefe Berechtigungen auf der Storage Box."
    fi
fi
