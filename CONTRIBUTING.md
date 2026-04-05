# Mitmachen / Contributing

Gut Pfad! 👋 Willkommen bei den `infrastructure-configs` der DPSG-Eschborn.

Wir freuen uns sehr, falls du mithelfen möchtest, das Setup für unsere Serverlandschaft noch einfacher, sicherer und besser zu machen. Dieses Repository ist absichtlich so aufgebaut, dass du als Einsteiger schnell mitmischen kannst. Anstelle von hochkomplexen Tools für das grundlegende Server-Setup setzen wir hier auf isolierte **Docker-Container** kombiniert mit leicht lesbaren **Bash-Skripten**.

## So kannst du beitragen

### 1. Ein neues Plugin/Modul hinzufügen

Du möchtest z.B. ein Wiki (Wiki.js) oder eine custom Pfadfinder Buchführungs-WebApp ergänzen?
Großartig! So einfach geht's:

1. Mach einen Fork von diesem Repository.
2. Lege einen neuen Ordner in `/extensions` an (z.B. `/extensions/wiki`).
3. Das Herzstück ist die `manifest.env`: Beschreibt die Metadaten. Damit taucht dein Tool automatisch im Start-Menü auf!
4. Du kannst dich in unseren **Plugin-Lifecycle** einklinken, indem du optionale Script-Dateien (Hooks) in dein Verzeichnis legst:
   - `validate.sh` (Abhängigkeiten prüfen)
   - `configure.sh` (User befragen)
   - `.env.example` (Umgebungsvariablen-Template)
   - `pre-deploy.sh` / `post-deploy.sh` (Host-Level Setup ausführen)
   - `docker-compose.yml` (Container starten)
5. Sende einen Pull Request!

Weitere Details zur genauen Syntax der `manifest.env` und der API (Variablen wie `SYSTEM_DOMAIN`), auf die deine Scripts zugreifen können, findest du im Guide zu unserer Architektur unter [docs/plugin-entwicklung.md](docs/plugin-entwicklung.md).

### 2. Bugs und Verbesserungen

Wenn du einen Fehler im Haupt-Skript `setup.sh` oder im `bootstrap.sh` findest, denk bei deiner Fehlerbehebung bitte an unsere P10 "Goldene Regeln":

- **Idempotenz:** Man muss dein Skript unendlich oft hintereinander ausführen können, ohne das die Konfiguration zerfällt.
- **Fail-Fast:** Nutze `set -euo pipefail` in Bash-Skripten, um unvorhersehbares Fehlverhalten frühzeitig zu stoppen.
- **Atomic Writes:** Modifikationen an Konfigurationsdateien sollen wenn möglich über temporäre Dateien ablaufen, die abschließend via `mv` ersetzt werden.
- **Kommentare:** Schreibe minimalen, aber klaren Code. "Was" passiert, steht im Code. "Warum" es hier steht, schreibst du in den Kommentar.

### Los geht's

Hab keine Angst vor Fehlern. Wir lernen hier alle gemeinsam! Bei Fragen mach einfach ein GitHub Issue auf.
