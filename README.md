# 🏕️ Pfadfinder-Cloud: Infrastructure Configs

Gut Pfad! 👋 Dieses Repository enthält die Basis-Infrastruktur für automatisierte Server-Einrichtungen im DPSG-Eschborn Verbund. Es ist darauf ausgelegt, leicht verständlich, sicher (P10 Standard) und extrem modular zu sein.

## Architektur-Prinzipien
1. **Docker-First:** Jeder Dienst (z.B. Nextcloud, Traefik) läuft isoliert in Containern.
2. **Modularität:** Neue Dienste erfordern lediglich einen eigenen Unterordner im `extensions`-Verzeichnis inklusive eines `manifest.env`. Die Installation wird automatisch daraus generiert.
3. **Idempotenz:** Installationsskripte können beliebig oft ausgeführt werden, ohne bestehende Setups zu beschädigen.

---

## Installation

### A) Homeserver oder Raspberry Pi (Manuelles Setup)
Führe auf einem frischen Ubuntu-Server (24.04 empfohlen) den folgenden Befehl als "root" aus. *(Tipp: Wenn du davor `sudo su` eintippst, bist du root)*:

```bash
bash <(curl -sL https://raw.githubusercontent.com/DPSG-Eschborn/infrastructure-configs/main/bootstrap.sh)
```
Das Skript installiert notwendige Abhängigkeiten, klont dieses Repository nach `/opt/pfadfinder-cloud` und startet den Einrichtungs-Assistenten.

### B) Cloud-Server (z.B. Hetzner via Cloud-Init)
Nutze unsere `cloud-configs/hetzner-basic-node.yaml` Datei beim Erstellen des Servers im Feld "User Data" bzw. "Cloud Config". Das System aktualisiert sich automatisch und führt das Setup vollständig im Hintergrund aus, ohne dass ein SSH-Login notwendig ist.

---

## Dokumentation

Die genaue Funktionsweise der Komponenten ist hier dokumentiert:

- [Installationsablauf für Hetzner Cloud](./docs/hetzner-installation.md)
- [Installationsablauf für lokale Server](./docs/homeserver-installation.md)
- [Architektur und Plugin-Entwicklung](./docs/plugin-entwicklung.md)

Für Hinweise zur Entwicklung und Integration neuer Module siehe die [CONTRIBUTING.md](./CONTRIBUTING.md).
