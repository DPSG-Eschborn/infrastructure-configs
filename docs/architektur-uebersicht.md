# 🏕️ Pfadfinder-Cloud — Architektur & User-Flow

Diese Seite erklärt den gesamten Ablauf: Vom Start des Assistenten bis zum laufenden Server.

---

## Der große Überblick

```mermaid
flowchart TD
    START["Assistent starten"] --> WIZARD["Wizard startet"]

    WIZARD --> Q1{"Wo soll der Server laufen?"}

    Q1 -->|"1 Hetzner Cloud"| H_TOKEN["API-Token eingeben"]
    Q1 -->|"2 Eigener Server"| SSH_IP["IP eingeben"]
    Q1 -->|"3 Lokal"| LOCAL["Kein Input"]

    H_TOKEN --> CONFIG
    SSH_IP --> CONFIG
    LOCAL --> CONFIG

    CONFIG["Konfiguration sammeln"]
    CONFIG --> C_DOMAIN{"Domain?"}
    C_DOMAIN -->|"Ja"| DOMAIN_SET["HTTPS + Lets Encrypt"]
    C_DOMAIN -->|"Leer"| DOMAIN_AUTO["HTTP Testmodus"]

    DOMAIN_SET --> MODULES
    DOMAIN_AUTO --> MODULES

    MODULES["Module auswaehlen"]

    MODULES --> SB{"Storage Box?"}
    SB -->|"Ja"| SB_CRED["SB-Zugangsdaten"]
    SB -->|"Nein"| DISK{"Externe Festplatte?"}
    SB_CRED --> CONFIRM
    DISK -->|"Ja"| DISK_PATH["Pfad angeben"]
    DISK -->|"Nein"| CONFIRM
    DISK_PATH --> CONFIRM

    CONFIRM["Zusammenfassung bestaetigen"]
    CONFIRM --> DEPLOY{"Deploy!"}

    DEPLOY -->|"Hetzner"| H_DEPLOY["API erstellt Server mit Cloud-Init"]
    DEPLOY -->|"SSH"| SSH_DEPLOY["SSH + bootstrap.sh"]
    DEPLOY -->|"Lokal"| L_DEPLOY["sudo bootstrap.sh"]

    H_DEPLOY --> DONE
    SSH_DEPLOY --> DONE
    L_DEPLOY --> DONE

    DONE["URLs + Zugangsdaten anzeigen"]

    style START fill:#4CAF50,color:white
    style DONE fill:#4CAF50,color:white
    style CONFIG fill:#2196F3,color:white
    style DEPLOY fill:#FF9800,color:white
```

---

## Phase 1: Einstieg — Drei Wege zum Assistenten

Der Assistent ist auf **jedem Betriebssystem** aufrufbar:

| Betriebssystem | Einstieg | Datei |
| --- | --- | --- |
| **Windows** (Option A) | `deploy.bat` herunterladen + Doppelklick | `deploy.bat` lädt `deploy.ps1` automatisch von GitHub |
| **Windows** (Option B) | PowerShell-Einzeiler | `irm URL -OutFile ...; & ...` |
| **Linux / macOS** | Terminal-Einzeiler | `curl -sL URL -o /tmp/deploy.sh && bash /tmp/deploy.sh` |
| **Direkt am Server** | Terminal | `sudo ./setup.sh --interactive` |

> **Hinweis:** `deploy.bat` ist standalone — es enthält keinen Code, sondern lädt `deploy.ps1` bei jeder Ausführung frisch von GitHub herunter. So ist der Assistent immer auf dem neuesten Stand.

---

## Phase 2: Provider-Auswahl — Die 3 Wege

### Weg 1: Hetzner Cloud (Vollautomat)

```mermaid
sequenceDiagram
    participant U as User
    participant W as Wizard
    participant API as Hetzner API
    participant SRV as Neuer Server

    U->>W: Waehlt Hetzner Cloud
    W->>U: Fragt nach API-Token
    U->>W: Token eingeben
    W->>API: GET /ssh_keys Token testen
    API-->>W: 200 OK

    W->>U: Fragt nach Domain und Modulen
    U->>W: Konfiguration eingeben

    W->>W: Cloud-Init YAML generieren
    W->>API: POST /servers mit Cloud-Init
    API-->>W: Server-ID + IP + Root-Passwort

    W->>W: Pollt API bis Status running

    Note over SRV: Server bootet und Cloud-Init laeuft
    Note over SRV: 1. OS-Haertung: fail2ban + UFW + Updates
    Note over SRV: 2. git clone Repo
    Note over SRV: 3. setup.sh headless
    Note over SRV: 4. Docker + Traefik + Nextcloud

    W->>U: Zeigt IP und URLs und Root-Passwort
```

**Was der User eingeben muss:**

1. Hetzner API-Token (5 Klicks in der Hetzner Console)
2. Optional: GitHub-Username (für SSH-Zugang per Key)
3. Domain (oder leer für Testmodus)
4. Module auswählen (y/n pro Modul)
5. Optional: Storage Box oder externe Festplatte

### Weg 2: Eigener Server (SSH)

```mermaid
sequenceDiagram
    participant U as User
    participant W as Wizard
    participant SRV as Linux-Server

    U->>W: Waehlt Eigener Server
    W->>U: Fragt nach IP + Port
    U->>W: z.B. 123.45.67.89

    W->>U: Fragt nach Domain und Modulen
    U->>W: Konfiguration eingeben

    W->>W: Baut Setup-Befehl
    W->>W: Base64-kodiert fuer Escaping-Schutz

    W->>SRV: ssh root@IP echo BASE64 und base64 -d und bash
    Note over U: User tippt Root-Passwort

    Note over SRV: bootstrap.sh laeuft
    Note over SRV: 1. apt install git curl
    Note over SRV: 2. git clone Repo
    Note over SRV: 3. STORAGEBOX_PASS=xxx setup.sh headless

    SRV-->>W: Exit Code 0
    W->>U: Zeigt URLs
```

> **Sicherheit:** Das StorageBox-Passwort wird als **Environment-Variable** übergeben (`STORAGEBOX_PASS='...' ./setup.sh`), nicht als CLI-Argument. Dadurch ist es weder in `ps aux` noch in Logfiles sichtbar.

### Weg 3: Lokal (Homeserver / Raspberry Pi)

Identisch zu Weg 2, aber ohne SSH. Das Skript erkennt automatisch ob Root-Rechte vorhanden sind und fragt bei Bedarf nach dem `sudo`-Passwort. Nur sinnvoll wenn der User direkt am Server-Terminal sitzt.

---

## Phase 3: Konfiguration — Was passiert im Detail

```mermaid
flowchart LR
    subgraph "Wizard sammelt Konfig"
        D["Domain?"] --> M["Module?"]
        M --> S["Storage Box?"]
        S --> DISK["Ext. Festplatte?"]
    end

    subgraph "setup.sh verarbeitet"
        HARD["OS-Haertung"] --> ENV["Generiert .env aus .env.example"]
        ENV --> PLACE["Ersetzt Platzhalter"]
        PLACE --> DATADIR["Setzt NEXTCLOUD_DATA_DIR"]
        DATADIR --> DOCKER["docker compose up -d"]
    end

    DISK --> |"headless Args + Env-Vars"| HARD
```

### Das Platzhalter-System

So werden aus Templates echte Konfigurationen:

```text
.env.example (Template)               .env (Generiert)
─────────────────────────             ──────────────────────────
DOMAIN_NAME=DOMAIN_PLACEHOLDER    →   DOMAIN_NAME=dpsg-muster.de
DB_PASSWORD=PASSWORD_PLACEHOLDER  →   DB_PASSWORD=a7f3b2c9e8d1...
NEXTCLOUD_DATA_DIR=nextcloud_...  →   NEXTCLOUD_DATA_DIR=/mnt/storagebox-data
```

| Platzhalter | Wird ersetzt durch | Woher kommt der Wert? |
| --- | --- | --- |
| `DOMAIN_PLACEHOLDER` | Domain oder IP.nip.io | User-Eingabe oder AUTO-Erkennung |
| `PASSWORD_PLACEHOLDER` | Zufällig generiert (32 Zeichen hex) | `openssl rand -hex 16` |
| `STORAGEBOX_PLACEHOLDER` | z.B. `u123456` | User-Eingabe im Dialog |
| `STORAGEBOXPW_PLACEHOLDER` | Storage-Box-Passwort | User-Eingabe (verdeckt) |

### Nextcloud Data-Directory

Das Datenverzeichnis wird **während der .env-Generierung** gesetzt (nicht nachträglich). Priorität:

1. **StorageBox aktiv** → `/mnt/storagebox-data`
2. **Externe Festplatte** → `/mnt/nextcloud-data` (oder `--data-dir` Pfad)
3. **Nichts konfiguriert** → Standard (`nextcloud_userdata` Docker-Volume)

---

## Phase 4: Deployment — Was auf dem Server passiert

```mermaid
flowchart TD
    BS["bootstrap.sh"] --> GIT["git clone Repo nach /opt/pfadfinder-cloud"]
    GIT --> SETUP["setup.sh startet"]

    SETUP --> DOCKER_INSTALL{"Docker installiert?"}
    DOCKER_INSTALL -->|"Nein"| INSTALL["Docker installieren"]
    DOCKER_INSTALL -->|"Ja"| HARDEN
    INSTALL --> HARDEN

    HARDEN["OS-Haertung"]

    HARDEN --> F2B["fail2ban: SSH Brute-Force-Schutz"]
    F2B --> UPG["unattended-upgrades: Auto-Patches"]
    UPG --> UFW["UFW Firewall: nur 22 + 80 + 443"]

    UFW --> SCAN["Scanne Module via manifest.env"]

    SCAN --> TEST{"Domain = .nip.io?"}
    TEST -->|"Ja"| HTTP["TEST-MODUS: HTTPS deaktivieren"]
    TEST -->|"Nein"| HTTPS["PRODUKTIV-MODUS: HTTPS + Lets Encrypt"]

    HTTP --> NET
    HTTPS --> NET

    NET["Docker-Netzwerk pfadfinder_net"]

    NET --> LOOP["Fuer jedes Modul:"]

    LOOP --> ENV_GEN[".env generieren + Data-Dir setzen"]
    ENV_GEN --> TYPE{"mount.sh vorhanden?"}
    TYPE -->|"Ja"| MOUNT["bash mount.sh"]
    TYPE -->|"Nein"| COMPOSE["docker compose up -d"]

    MOUNT --> NEXT["Naechstes Modul"]
    COMPOSE --> NEXT
    NEXT -->|"Weitere"| LOOP
    NEXT -->|"Fertig"| URLS["URLs anzeigen"]

    style BS fill:#FF9800,color:white
    style HARDEN fill:#E91E63,color:white
    style URLS fill:#4CAF50,color:white
```

---

## Die Modul-Reihenfolge

Die Reihenfolge ist wichtig — Module werden in der Install-Reihenfolge gestartet:

| # | Modul | Typ | Was es macht |
| --- | --- | --- | --- |
| 1 | `core` (Traefik) | docker-compose | Reverse Proxy + SSL-Zertifikate + Security-Headers |
| 2 | `storagebox` | mount.sh | CIFS-Mount der Hetzner Storage Box |
| 3 | `nextcloud` | docker-compose | Cloud-Speicher + MariaDB Datenbank |
| 4 | `website` | docker-compose | Statische Stammes-Homepage |

> **Warum diese Reihenfolge?**
>
> - Traefik muss zuerst laufen (andere Module registrieren sich dort per Docker-Labels)
> - Storage Box muss **vor** Nextcloud gemountet sein (Nextcloud braucht den Mount-Pfad beim Start)
> - Nextcloud Data-Dir wird **bei der .env-Generierung** gesetzt, nicht nachträglich

---

## Sicherheits-Architektur

Jeder Server wird automatisch gehärtet — sowohl über Cloud-Init (Hetzner) als auch durch setup.sh (alle Provider):

| Maßnahme | Implementierung | Schutz gegen |
| --- | --- | --- |
| **fail2ban** | SSH-Jail, automatische IP-Sperre | Brute-Force-Angriffe |
| **UFW Firewall** | deny-all + Whitelist 22/80/443 | Port-Scanning, unerwünschter Zugriff |
| **unattended-upgrades** | Automatische Sicherheitspatches | Bekannte Schwachstellen |
| **SSH-Härtung** | Root-Login verboten, Max. 3 Versuche | SSH-Brute-Force |
| **Security-Headers** | HSTS, X-Frame-Options, CSP via Traefik | XSS, Clickjacking |
| **Passwort-Handling** | Env-Vars statt CLI-Args, `openssl rand` | Klartext-Leaks in Logs/Prozessliste |
| **Atomic Writes** | .env wird in .env.tmp geschrieben, dann `mv` | Halb-generierte Konfigurationen |

---

## Datei-Architektur — Was gehört wohin

```text
infrastructure-configs/
│
├── deploy.bat                 ← Windows: Doppelklick-Einstieg (standalone, laedt deploy.ps1 von GitHub)
├── deploy.ps1                 ← Windows-Wizard (Provider-Auswahl + Konfig)
├── deploy.sh                  ← Linux/macOS-Wizard (identische Funktionalitaet)
│
├── bootstrap.sh               ← Auf dem SERVER: klont Repo + startet setup.sh
├── setup.sh                   ← Auf dem SERVER: Deployment-Engine + OS-Haertung
│
├── cloud-configs/
│   └── hetzner-basic-node.yaml    ← Cloud-Init Template (manuelle Alternative)
│
├── core/
│   └── traefik/               ← MUSS immer installiert werden
│       ├── manifest.env           (Plugin-Metadaten)
│       ├── .env.example           (Template: Domain)
│       └── docker-compose.yml     (Container + Security-Headers Middleware)
│
└── extensions/
    ├── nextcloud/             ← Optionales Modul: Cloud-Speicher
    │   ├── manifest.env
    │   ├── .env.example           (Template: Domain, DB-Passwort, Data-Dir)
    │   └── docker-compose.yml
    │
    ├── storagebox/            ← Optionales Modul: Hetzner Storage Box
    │   ├── manifest.env
    │   ├── .env.example           (Template: SB-User, SB-Passwort)
    │   └── mount.sh               (KEIN Docker — Host-Level CIFS-Mount)
    │
    └── website/               ← Optionales Modul: Homepage
        ├── manifest.env
        ├── .env.example           (Template: Domain)
        ├── docker-compose.yml
        └── html/index.html
```

---

## Neues Modul hinzufügen

Wenn jemand ein neues Plugin bauen will (z.B. eine Kassen-Software), sind nur 3 Dateien nötig:

```mermaid
flowchart LR
    A["1. Ordner anlegen: extensions/kasse/"] --> B["2. manifest.env"]
    B --> C["3. .env.example"]
    C --> D["4. docker-compose.yml oder mount.sh"]
    D --> E["Fertig! Taucht automatisch im Setup-Menue auf"]

    style E fill:#4CAF50,color:white
```

**Kein Code in `setup.sh` ändern nötig** — das Manifest wird beim nächsten Start automatisch erkannt.

Eine ausführliche Anleitung dazu steht in [Plugin-Entwicklung](./plugin-entwicklung.md).
