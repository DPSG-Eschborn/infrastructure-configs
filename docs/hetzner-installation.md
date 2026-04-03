# Hetzner Cloud (Cloud-Init Mechanismus)

Bei einem gemieteten Server (z.B. Hetzner Cloud, AWS oder DigitalOcean) kann der **Cloud-Init** Mechanismus zur automatisierten Erstkonfiguration genutzt werden.

## Was ist Cloud-Init?
Cloud-Init ist ein Industriestandard zur Initialisierung von Cloud-Instanzen. Bei der Erstellung eines virtuellen Servers kann ein Konfigurationsskript ("Cloud Config" oder "User-Data") übergeben werden. Dieses wird beim ersten Start ausgeführt.

## Installationsprozess
Ein manueller SSH-Login ist für das initiale Setup nicht erforderlich. Der Cloud-Provider übergibt die `cloud-init.yaml` während des ersten Boot-Vorgangs an das Betriebssystem. Das Skript wird mit Root-Rechten ausgeführt, bevor das Netzwerk für reguläre Logins freigegeben wird.

### Ablauf (Am Beispiel des Nextcloud-Moduls)
1. Die Vorlage `cloud-configs/hetzner-basic-node.yaml` aus diesem Repository kopieren.
2. Die Vorlage bei der Servererstellung im Cloud-Panel im Feld "User Data" einfügen.
3. **Wichtig:** Scrolle im Code etwas runter und passe zwei kleine Dinge an deine Gruppe an:
   - Ersetze `pfadfinder-admin` durch deinen eigenen GitHub-Namen (damit verknüpft Hetzner automatisch deinen SSH-Key).
   - Ersetze ganz unten `cloud.unsere-domain.de` durch eure echte Pfadfinder-Domain.
4. Der Server startet.
5. Das System führt die Cloud-Init Anweisungen aus:
   - Systempakete aktualisieren (`apt-get update`).
   - Basis-Abhängigkeiten wie `git` und `curl` installieren.
   - Das Repository nach `/opt/pfadfinder-cloud/` klonen.
   - Das Setup-Skript im Headless-Modus mit deiner Domain ausführen.
6. Nach wenigen Minuten ist die Instanz gebootet und die Cloud über eure Domain erreichbar.

---

## Security & Qualitätsstandards (P10)

Um eine hohe Systemstabilität und Sicherheit zu gewährleisten, beinhaltet die `cloud-init.yaml` folgende Restriktionen:

1. **SSH Hardening:** Der Root-Login per Passwort wird grundsätzlich blockiert. Der Zugriff ist ausschließlich über kryptografische SSH-Keys (z.B. Ed25519) gestattet.
2. **UFW (Uncomplicated Firewall):** Eine restriktive Firewall ("Default Deny") wird aktiviert. Standardmäßig sind nur die Ports 80 (HTTP), 443 (HTTPS) und 22 (SSH) freigegeben. Einzelne Container werden dahinter gekapselt.
3. **Unattended Upgrades:** Der Server ist so konfiguriert, dass er automatisch tägliche Security-Patches des Betriebssystems installiert.
4. **Logging:** Die Ausgabe des Skripts `setup.sh` wird in `/var/log/pfadfinder-setup.log` persistiert, um Fehleranalysen im Nachhinein zu ermöglichen.
