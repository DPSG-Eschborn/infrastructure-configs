#!/bin/bash
# P10 Strict Mode
set -euo pipefail

# API:
# IN:  ASSISTANT_MODE, ACTIVE_MODULES, CUSTOM_DATA_DIR, MODULE_ENV_FILE
# OUT: Schreibt Konfiguration in MODULE_ENV_FILE

if [ "${ASSISTANT_MODE:-interactive}" != "interactive" ]; then
    exit 0
fi

# Wenn StorageBox aktiviert ist, oder CUSTOM_DATA_DIR schon gesetzt ist, nichts tun
if [[ ",$ACTIVE_MODULES," == *",storagebox,"* ]] || [ -n "${CUSTOM_DATA_DIR:-}" ]; then
    exit 0
fi

echo ""
read -p "Moechtest du eine externe Festplatte fuer Nextcloud nutzen? (y/n): " _disk_choice
if [[ ! "$_disk_choice" =~ ^[yYjJ] ]]; then
    exit 0
fi

echo ""
echo "============================================"
echo "   Externe Festplatte fuer Nextcloud"
echo "============================================"
echo ""
echo "[-] Suche nach verfuegbaren Festplatten..."

# System-Disk ermitteln (die Festplatte auf der / liegt)
root_source=$(findmnt -n -o SOURCE / 2>/dev/null || echo "")
# Device-Name ohne Partitionsnummer (z.B. /dev/sda1 -> /dev/sda)
root_disk=$(echo "$root_source" | sed 's/[0-9]*$//' | sed 's/p[0-9]*$//')

# Alle Block-Devices sammeln (ohne Loops, ROM, System-Disk)
disk_devs=()
disk_labels=()
while IFS= read -r line; do
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
    exit 0
fi

echo ""
echo "    Verfuegbare Festplatten:"
for i in "${!disk_labels[@]}"; do
    echo "    [$((i+1))] ${disk_labels[$i]}"
done
echo ""
echo "    [0] Keine — Standard-Speicher verwenden"
echo ""
read -p "Auswahl: " disk_choice

if [ -z "$disk_choice" ] || [ "$disk_choice" = "0" ]; then
    exit 0
fi

idx=$((disk_choice - 1))
if [ "$idx" -lt 0 ] || [ "$idx" -ge ${#disk_devs[@]} ]; then
    echo "[!] Ungueltige Auswahl."
    exit 0
fi

selected_dev="${disk_devs[$idx]}"
mount_point="/mnt/nextcloud-data"

# Erste Partition finden (oder Device selbst verwenden wenn keine Partitionen)
part_dev="$selected_dev"
first_part=$(lsblk -lnpo NAME,TYPE "$selected_dev" 2>/dev/null | awk '$2 == "part" {print $1; exit}')
if [ -n "$first_part" ]; then
    part_dev="$first_part"
fi

# Dateisystem pruefen
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
        exit 0
    fi
else
    echo "    -> Dateisystem erkannt: $fs_type"
fi

# Mount-Punkt erstellen
mkdir -p "$mount_point"

# fstab-Eintrag (idempotent: nur hinzufuegen wenn noch keiner existiert)
if ! grep -q " ${mount_point} " /etc/fstab 2>/dev/null; then
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
        exit 0
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

# In die Env-Datei schreiben, die von setup.sh ausgelesen wird
echo "CUSTOM_DATA_DIR=$mount_point" >> "$MODULE_ENV_FILE"

exit 0
