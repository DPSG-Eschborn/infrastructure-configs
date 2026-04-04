# Infrastruktur-Architektur: Module und Plugins

Diese Dokumentation beschreibt, wie die Skripte und Container-Konfigurationen logisch strukturiert sind und wie das Setup abgewickelt wird.

Die Architektur basiert auf **Docker Compose** zur Container-Steuerung und einem **Bash-Skript** (`setup.sh`) zur logischen Steuerung des Ablaufs. 

*Hintergrund:* Obwohl Tools wie Ansible weithin verbreitet sind, erfordern sie eine harte Einarbeitungszeit. Die Kombination aus Bash und Docker Compose ist für viele erfahrungsgemäß einfacher nachzuvollziehen. Das senkt die Hürde für administrative Eingriffe in unseren Pfadfinder-Lokalgruppen, falls abends mal ein Server streikt.

## Aufbau des Systems

### 1. Das Bootstrap-System
Dieses Rahmenwerk platziert das Repository initial auf dem Server:
- **Hetzner (Cloud):** Automatisiert über User-Data (Cloud-Init).
- **Self-Hosted:** Manuell initiiert über das `bootstrap.sh` Ausführungsskript.
*Ergebnis: Das Repository-System liegt unter `/opt/pfadfinder-cloud` vor.*

### 2. Das Hauptskript (`setup.sh`)
Dies ist der Installer, der auf jedem System ausgeführt wird. Die Hauptaufgaben:
1. Docker-Engine installieren, falls diese nicht auf dem System vorhanden ist.
2. Dynamisches Scanning der Modulverzeichnisse (Plugin Auto-Erkennung).
3. Interaktive Abfrage beim Benutzer (z.B. Domainname, Auswahl der spezifischen Dienste).
4. Sichere Erstellung von Umgebungsvariablen (`.env` Dateien generiert aus `.env.example`).
5. Sequenzielles Starten der ausgewaehlten Module (Docker-Container oder Host-Level-Skripte).

### 3. Das Modul-System 
Um das Installations-Skript (`setup.sh`) bei neuen Projekten nicht modifizieren zu müssen, baut das System auf einer autarken Plugin-Struktur auf. Modul-Ordner (wie `/extensions/nextcloud`) beinhalten grundsätzlich drei Dateien:

1. `manifest.env`: Enthält Metadaten fuer das Setup-Skript.
2. `docker-compose.yml` **oder** `mount.sh`: Definiert entweder einen Docker-Container oder ein Host-Level-Setup.
3. `.env.example`: Template fuer Konfigurationsparameter (wie Kennwörter oder Tokens).

Das Skript `setup.sh` sucht beim Start zur Laufzeit nach `manifest.env` Dateien und integriert diese dynamisch in die Modulauswahl der Benutzeroberfläche.

Beispiel für eine `manifest.env`:

```bash
MODULE_ID="nextcloud"
MODULE_NAME="Nextcloud (Basic)"
MODULE_DESCRIPTION="Die leichte, hochperformante Basic Variante der Nextcloud inkl. MariaDB Container."
```

## Verzeichnisstruktur

```text
infrastructure-configs/
├── README.md                      # Dokumentation und Verweise
├── bootstrap.sh                   # Init-Skript für Self-Hosted-Instanzen
├── setup.sh                       # Hauptskript für das Modul-Deployment
├── docs/                          # Architektur- und Prozessdokumentation
│   ├── hetzner-installation.md
│   ├── homeserver-installation.md
│   ├── storagebox-anbindung.md
│   └── plugin-entwicklung.md
├── cloud-configs/                 # Vorlagen für Cloud-Provider
│   └── hetzner-basic-node.yaml    # Cloud-Init Template
├── core/                          # Fundamentale Dienste
│   └── traefik/                   # Leichter Reverse-Proxy (SSL)
│       ├── docker-compose.yml
│       ├── .env.example
│       └── manifest.env
└── extensions/                    # Optionale Module
    ├── nextcloud/
    │   ├── docker-compose.yml
    │   ├── .env.example
    │   └── manifest.env
    ├── storagebox/                # Host-Level Modul (kein Docker)
    │   ├── mount.sh               # CIFS-Mount Skript
    │   ├── .env.example
    │   └── manifest.env
    └── website/
        ├── docker-compose.yml
        ├── .env.example
        ├── html/                   # Statische Website-Dateien
        │   └── index.html
        └── manifest.env
```

### 4. Modul-Typen

Das Setup-Skript erkennt automatisch, welcher Typ ein Modul ist:

| Datei im Modul-Ordner | Typ | Aktion von `setup.sh` |
| --- | --- | --- |
| `docker-compose.yml` | Container-Modul | `docker compose up -d` |
| `mount.sh` | Host-Level-Modul | `bash mount.sh` |

Dadurch koennen Module auch reine System-Konfigurationen durchfuehren (z.B. Dateisysteme mounten, Cron-Jobs einrichten), ohne einen Docker-Container zu benoetigen.

---

## Qualitätsstandards (P10)

Für alle Bash-Routinen in diesem Repository gelten strikte Struktur-Vorgaben:

1. **Idempotenz:** Skripte müssen beliebig oft ausführbar sein, ohne Korruption zu verursachen. Ein wiederholter Aufruf darf weder Konfigurationsdaten duplizieren noch Laufzeitfehler generieren.
2. **Strict Bash:** Alle ausführbaren Skripte definieren `set -euo pipefail`.
   - `-e`: Stoppt die Ausführung umgehend bei Fehlerrückgabewerten beliebiger Programme.
   - `-u`: Verhindert Operationen bei unbelegten Variablenwerten.
   - `-o pipefail`: Prüft Laufzeiten innerhalb einer Operations-Pipe (`cmdA | cmdB`).
3. **Atomic Writes:** Werden sicherheitskritische Konfigurationen modifiziert, geschieht das iterativ über temporäre Dateien (`*.env.tmp`). Ein anschließender `mv`-Befehl verhindert korrumpierte Dateistrukturen bei Hard-Resets der Maschine.
4. **Container-Isolation:** Subsysteme agieren in isolierten Netzwerkschichten (`pfadfinder_net`). Port-Mappings auf der System-Host-Ebene sind verboten; alle externen Zugriffsanfragen terminieren am Traefik Proxy.
