# 🏕️ Pfadfinder-Cloud — Architektur & User-Flow

Diese Seite erklärt den gesamten Ablauf: Vom Doppelklick auf `deploy.bat` bis zum laufenden Server.

---

## Der große Überblick

```mermaid
flowchart TD
    START(["👤 User doppelklickt deploy.bat"]) --> WIZARD["deploy.ps1 startet"]
    
    WIZARD --> Q1{"Wo soll der Server laufen?"}
    
    Q1 -->|"1 — Hetzner Cloud"| H_TOKEN["API-Token eingeben\n(wird live validiert)"]
    Q1 -->|"2 — Eigener Server"| SSH_IP["IP + Root-Passwort\neingeben"]
    Q1 -->|"3 — Lokal"| LOCAL["Kein Input nötig"]
    
    H_TOKEN --> CONFIG
    SSH_IP --> CONFIG
    LOCAL --> CONFIG
    
    CONFIG["Konfiguration\n(gleich für alle)"]
    CONFIG --> C_DOMAIN{"Domain eingeben?"}
    C_DOMAIN -->|"Ja"| DOMAIN_SET["z.B. dpsg-muster.de\n→ HTTPS + Let's Encrypt"]
    C_DOMAIN -->|"Leer lassen"| DOMAIN_AUTO["AUTO\n→ IP.nip.io\n→ HTTP Testmodus"]
    
    DOMAIN_SET --> MODULES
    DOMAIN_AUTO --> MODULES
    
    MODULES["Module auswählen:\n☑ Traefik (immer)\n☐ Nextcloud\n☐ Website\n☐ Storage Box"]
    
    MODULES --> CONFIRM["Zusammenfassung anzeigen\n→ User bestätigt"]
    
    CONFIRM --> DEPLOY{"Deploy!"}
    
    DEPLOY -->|Hetzner| H_DEPLOY["API erstellt Server\nmit Cloud-Init YAML"]
    DEPLOY -->|SSH| SSH_DEPLOY["SSH verbindet\nund führt bootstrap.sh aus"]
    DEPLOY -->|Lokal| L_DEPLOY["bootstrap.sh\nlokal ausführen"]
    
    H_DEPLOY --> DONE
    SSH_DEPLOY --> DONE
    L_DEPLOY --> DONE
    
    DONE(["✅ URLs + Zugangsdaten\nwerden angezeigt"])
    
    style START fill:#4CAF50,color:white
    style DONE fill:#4CAF50,color:white
    style CONFIG fill:#2196F3,color:white
    style DEPLOY fill:#FF9800,color:white
```

---

## Phase 1: Einstieg — Was der User sieht

Der User braucht nur zwei Dateien:

- **`deploy.bat`** — Das klickt der User an (Windows-Einstiegspunkt)
- **`deploy.ps1`** — Das führt die eigentliche Arbeit aus

`deploy.bat` ruft PowerShell mit `ExecutionPolicy Bypass` auf, damit keine Policy-Probleme entstehen. Der User muss **nichts installieren** — PowerShell und SSH sind seit Windows 10 eingebaut.

---

## Phase 2: Provider-Auswahl — Die 3 Wege

### Weg 1: Hetzner Cloud (Vollautomat)

```mermaid
sequenceDiagram
    participant U as 👤 User (Windows)
    participant PS as deploy.ps1
    participant API as Hetzner API
    participant SRV as Neuer Server
    
    U->>PS: Wählt "Hetzner Cloud"
    PS->>U: Fragt nach API-Token
    U->>PS: Token eingeben
    PS->>API: GET /ssh_keys (Token testen)
    API-->>PS: 200 OK ✅
    
    PS->>U: Fragt nach Domain, Modulen etc.
    U->>PS: Konfiguration eingeben
    
    PS->>PS: Generiert Cloud-Init YAML
    PS->>API: POST /servers (mit Cloud-Init)
    API-->>PS: Server-ID + IP + Root-Passwort
    
    PS->>PS: Pollt API bis Status = "running"
    
    Note over SRV: Server bootet...
    Note over SRV: Cloud-Init läuft:
    Note over SRV: 1. git clone Repo
    Note over SRV: 2. setup.sh --headless
    Note over SRV: 3. Docker + Traefik + Nextcloud
    
    PS->>U: Zeigt IP, URLs, Root-Passwort
```

**Was der User eingeben muss:**

1. Hetzner API-Token (5 Klicks in der Hetzner Console)
2. Optional: GitHub-Username (für SSH-Zugang)
3. Domain (oder leer für Testmodus)
4. Module auswählen (y/n pro Modul)

### Weg 2: Eigener Server (SSH)

```mermaid
sequenceDiagram
    participant U as 👤 User (Windows)
    participant PS as deploy.ps1
    participant SRV as Linux-Server
    
    U->>PS: Wählt "Eigener Server"
    PS->>U: Fragt nach IP + Port
    U->>PS: z.B. 123.45.67.89
    
    PS->>U: Fragt nach Domain, Modulen etc.
    U->>PS: Konfiguration eingeben
    
    PS->>PS: Baut Setup-Befehl
    PS->>PS: Base64-kodiert (Escaping-Schutz)
    
    PS->>SRV: ssh root@IP "echo BASE64 | base64 -d | bash"
    Note over U: User tippt Root-Passwort
    
    Note over SRV: bootstrap.sh läuft:
    Note over SRV: 1. apt install git curl
    Note over SRV: 2. git clone Repo
    Note over SRV: 3. setup.sh --headless --install=... --domain=...
    
    SRV-->>PS: Exit Code 0
    PS->>U: Zeigt URLs
```

**Was der User eingeben muss:**

1. IP-Adresse des Servers
2. Root-Passwort (im SSH-Prompt)
3. Domain + Module (wie oben)

### Weg 3: Lokal (Homeserver / Raspberry Pi)

Identisch zu Weg 2, aber ohne SSH. Das Skript läuft direkt auf dem Linux-Server. Nur sinnvoll wenn der User am Server-Terminal selbst sitzt.

---

## Phase 3: Konfiguration — Was passiert im Detail

```mermaid
flowchart LR
    subgraph "deploy.ps1 sammelt Konfig"
        D["Domain?"] --> M["Module?"] --> S["Storage Box?"]
    end
    
    subgraph "setup.sh verarbeitet"
        ENV["Generiert .env\naus .env.example"] --> PLACE["Ersetzt Platzhalter:\nDOMAIN_PLACEHOLDER\nPASSWORD_PLACEHOLDER\nSTORAGEBOX_PLACEHOLDER"]
        PLACE --> DOCKER["docker compose up -d\n(oder mount.sh)"]
    end
    
    S --> |"--headless\n--install=core,nextcloud\n--domain=AUTO"| ENV
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

---

## Phase 4: Deployment — Was auf dem Server passiert

```mermaid
flowchart TD
    BS["bootstrap.sh"] --> GIT["git clone\nDPSG-Eschborn/infrastructure-configs\n→ /opt/pfadfinder-cloud"]
    GIT --> SETUP["setup.sh startet"]
    
    SETUP --> DOCKER_INSTALL{"Docker\ninstalliert?"}
    DOCKER_INSTALL -->|Nein| INSTALL["curl get.docker.com\nDocker installieren"]
    DOCKER_INSTALL -->|Ja| SCAN
    INSTALL --> SCAN
    
    SCAN["Scanne Module\n(manifest.env Dateien)"]
    
    SCAN --> TEST{"Domain = .nip.io?"}
    TEST -->|Ja| HTTP["TEST-MODUS\nHTTPS deaktivieren\nCertresolver entfernen"]
    TEST -->|Nein| HTTPS["PRODUKTIV-MODUS\nHTTPS + Let's Encrypt"]
    
    HTTP --> NET
    HTTPS --> NET
    
    NET["Docker-Netzwerk\npfadfinder_net erstellen"]
    
    NET --> LOOP["Für jedes Modul:"]
    
    LOOP --> ENV_GEN[".env generieren\n(Platzhalter ersetzen)"]
    ENV_GEN --> TYPE{"mount.sh\nvorhanden?"}
    TYPE -->|Ja| MOUNT["bash mount.sh\n(z.B. CIFS-Mount)"]
    TYPE -->|Nein| COMPOSE["docker compose up -d"]
    
    MOUNT --> NEXT["Nächstes Modul"]
    COMPOSE --> NEXT
    NEXT -->|Weitere| LOOP
    NEXT -->|Fertig| URLS["URLs anzeigen 🎉"]
    
    style BS fill:#FF9800,color:white
    style URLS fill:#4CAF50,color:white
```

---

## Die Modul-Reihenfolge

Die Reihenfolge ist wichtig — Module werden in der Install-Reihenfolge gestartet:

| # | Modul | Typ | Was es macht |
| --- | --- | --- | --- |
| 1 | `core` (Traefik) | docker-compose | Reverse Proxy + SSL-Zertifikate |
| 2 | `storagebox` | mount.sh | CIFS-Mount der Hetzner Storage Box |
| 3 | `nextcloud` | docker-compose | Cloud-Speicher + MariaDB Datenbank |
| 4 | `website` | docker-compose | Statische Stammes-Homepage |

> **Warum diese Reihenfolge?**
>
> - Traefik muss zuerst laufen (andere Module registrieren sich dort per Docker-Labels)
> - Storage Box muss vor Nextcloud gemountet sein (Nextcloud braucht den Mount-Pfad beim Start)

---

## Datei-Architektur — Was gehört wohin

```text
infrastructure-configs/
│
├── deploy.bat                 ← USER KLICKT HIER
├── deploy.ps1                 ← Windows-Wizard (Provider-Auswahl + Konfig)
│
├── bootstrap.sh               ← Auf dem SERVER: klont Repo + startet setup.sh
├── setup.sh                   ← Auf dem SERVER: die eigentliche Deployment-Engine
│
├── cloud-configs/
│   └── hetzner-basic-node.yaml    ← Cloud-Init Template (manuelle Alternative)
│
├── core/
│   └── traefik/               ← MUSS immer installiert werden
│       ├── manifest.env           (Plugin-Metadaten)
│       ├── .env.example           (Template: Domain)
│       └── docker-compose.yml     (Container-Definition)
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
    A["1. Ordner anlegen\nextensions/kasse/"] --> B["2. manifest.env\nMODULE_ID=kasse\nMODULE_NAME=..."]
    B --> C["3. .env.example\n(Optional: Platzhalter)"]
    C --> D["4. docker-compose.yml\n(oder mount.sh)"]
    D --> E["Fertig!\nTaucht automatisch\nim Setup-Menü auf"]
    
    style E fill:#4CAF50,color:white
```

**Kein Code in `setup.sh` ändern nötig** — das Manifest wird beim nächsten Start automatisch erkannt.

Eine ausführliche Anleitung dazu steht in [Plugin-Entwicklung](./plugin-entwicklung.md).
