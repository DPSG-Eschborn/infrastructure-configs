# Hetzner Storage Box Anbindung

Mit dem Modul `storagebox` kann eine [Hetzner Storage Box](https://www.hetzner.com/storage/storage-box/) als günstiger Massenspeicher für die Nextcloud-Benutzerdaten eingebunden werden.

## Voraussetzungen

1. Eine aktive Hetzner Storage Box (buchbar über [hetzner.com](https://www.hetzner.com/storage/storage-box/)).
2. **SMB/Samba-Support muss aktiviert sein.** Das geht so:
   - In die [Hetzner Console](https://console.hetzner.com/) einloggen.
   - Storage Box auswählen.
   - Unter „Einstellungen" den Punkt „Samba" aktivieren.
   - Einige Minuten warten, bis die Änderung aktiv ist.
3. Den **Username** (z.B. `u123456`) und das **Passwort** der Storage Box bereithalten.

## Architektur: Was liegt wo?

| Daten | Speicherort | Warum? |
|---|---|---|
| MariaDB (Datenbank) | Lokale SSD | Datenbanken brauchen schnelle IOPS |
| Nextcloud App-Code (PHP) | Lokale SSD | Schnelle Antwortzeiten im Browser |
| **Nextcloud User-Dateien** | **Storage Box** | Fotos, Dokumente etc. — hier sitzt das Volumen |
| Thumbnails & Previews | Lokale SSD | Werden von Nextcloud gecacht |

Dieser Hybrid-Ansatz kombiniert die Geschwindigkeit der lokalen SSD für zeitkritische Operationen mit dem günstigen Preis der Storage Box für den Massenspeicher (z.B. 1 TB ab ca. 3,81 €/Monat).

## Was macht das Skript automatisch?

Das Setup-Modul (`extensions/storagebox/mount.sh`) führt folgende Schritte gemäß der [offiziellen Hetzner-Dokumentation](https://docs.hetzner.com/robot/storage-box/access/access-samba-cifs/) aus:

1. **Installiert `cifs-utils`** (das Linux-Paket für SMB/CIFS-Mounts)
2. **Erstellt eine sichere Credentials-Datei** unter `/etc/storagebox-credentials.txt` (chmod 600 — nur root kann lesen)
3. **Erstellt das Mount-Verzeichnis** `/mnt/storagebox-data`
4. **Fügt einen Eintrag in `/etc/fstab` hinzu** für den automatischen Mount bei jedem Serverstart:
   ```
   //u123456.your-storagebox.de/backup /mnt/storagebox-data cifs iocharset=utf8,rw,seal,credentials=/etc/storagebox-credentials.txt,uid=33,gid=33,file_mode=0770,dir_mode=0770,nofail,_netdev 0 0
   ```
5. **Mountet die Storage Box sofort** und validiert den Schreibzugriff
6. **Setzt `NEXTCLOUD_DATA_DIR`** in der Nextcloud-Konfiguration auf `/mnt/storagebox-data`

### Erklärung der Mount-Optionen

| Option | Bedeutung |
|---|---|
| `seal` | SMB-Verbindung wird verschlüsselt (Hetzner-Empfehlung) |
| `uid=33,gid=33` | Dateien gehören dem User `www-data` (Nextcloud im Docker-Container) |
| `nofail` | Server bootet auch wenn die Storage Box nicht erreichbar ist |
| `_netdev` | Mount erst nachdem das Netzwerk steht |
| `credentials=...` | Passwort in separater Datei statt in fstab (Sicherheit) |

## Storage Box nachträglich hinzufügen

Wenn Nextcloud bereits ohne Storage Box läuft und die Box nachgerüstet werden soll:

1. **Setup erneut ausführen:**
   ```bash
   cd /opt/pfadfinder-cloud
   ./setup.sh --interactive
   ```
   Wähle im Dialog **nur** das Storage-Box-Modul aus.

2. **Bestehende Daten migrieren** (optional, falls bereits Dateien in Nextcloud hochgeladen wurden):
   ```bash
   # Nextcloud stoppen
   cd /opt/pfadfinder-cloud/extensions/nextcloud
   docker compose down

   # Daten von lokalem Volume auf Storage Box kopieren
   rsync -avP /var/lib/docker/volumes/nextcloud_nextcloud_userdata/_data/ /mnt/storagebox-data/

   # Nextcloud mit neuem Data-Dir starten
   docker compose up -d
   ```

3. **Nextcloud Data-Dir umstellen** (falls nicht bereits durch setup.sh geschehen):
   Editiere `/opt/pfadfinder-cloud/extensions/nextcloud/.env`:
   ```
   NEXTCLOUD_DATA_DIR=/mnt/storagebox-data
   ```

## Storage Box wieder abklemmen

Falls die Storage Box nicht mehr gebraucht wird:

1. Nextcloud stoppen: `cd /opt/pfadfinder-cloud/extensions/nextcloud && docker compose down`
2. In `/opt/pfadfinder-cloud/extensions/nextcloud/.env` den Wert zurücksetzen: `NEXTCLOUD_DATA_DIR=nextcloud_userdata`
3. Den fstab-Eintrag für `/mnt/storagebox-data` entfernen: `nano /etc/fstab`
4. Storage Box unmounten: `umount /mnt/storagebox-data`
5. Nextcloud neu starten: `docker compose up -d`

## Fehlerbehebung

| Problem | Lösung |
|---|---|
| Mount schlägt fehl | SMB in der Hetzner Console aktiviert? Warte 5 Minuten nach Aktivierung. |
| „Permission denied" | Username/Passwort prüfen. Credentials-Datei korrekt? (`cat /etc/storagebox-credentials.txt`) |
| Port 445 blockiert | Manche Provider blockieren Port 445. Prüfe mit: `nc -zv u123456.your-storagebox.de 445` |
| Dateien > 4 GB fehlerhaft | Hetzner-bekanntes Problem. Fix: In `/etc/fstab` die Option `cache=none` ergänzen. |
