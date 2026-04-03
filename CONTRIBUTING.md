# Mitmachen / Contributing

Gut Pfad! 👋 Willkommen bei den `infrastructure-configs` der DPSG-Eschborn.

Wir freuen uns sehr, falls du mithelfen möchtest, das Setup für unsere Serverlandschaft noch einfacher, sicherer und besser zu machen. Dieses Repository ist absichtlich so aufgebaut, dass du als Einsteiger schnell mitmischen kannst. Anstelle von hochkomplexen Tools für das grundlegende Server-Setup setzen wir hier auf isolierte **Docker-Container** kombiniert mit leicht lesbaren **Bash-Skripten**.

## So kannst du beitragen

### 1. Ein neues Plugin/Modul hinzufügen
Du möchtest z.B. ein Wiki (Wiki.js) oder unsere Pfadfinder Kassen-Software ergänzen?
Großartig! So einfach geht's:

1. Mach einen Fork von diesem Repository.
2. Lege einen neuen Ordner in `/extensions` an (z.B. `/extensions/wiki`).
3. Füge folgende drei Dateien in dieses Verzeichnis ein:
   - `docker-compose.yml`: Die Container-Konfiguration inkl. Routing-Labels für Traefik.
   - `.env.example`: Template für Umgebungsvariablen.
   - `manifest.env`: Beschreibt die Metadaten des Moduls. (Wird von unserem Main-Script gescannt. Damit taucht dein Tool automatisch im Start-Menü auf!).
4. Sende einen Pull Request!

Weitere Details zur genauen Syntax der `manifest.env` findest du im Guide zu unserer Architektur unter `docs/plugin-entwicklung.md`.

### 2. Bugs und Verbesserungen
Wenn du einen Fehler im Haupt-Skript `setup.sh` oder im `bootstrap.sh` findest, denk bei deiner Fehlerbehebung bitte an unsere P10 "Goldene Regeln":
- **Idempotenz:** Man muss dein Skript unendlich oft hintereinander ausführen können, ohne das die Konfiguration zerfällt.
- **Fail-Fast:** Nutze `set -euo pipefail` in Bash-Skripten, um unvorhersehbares Fehlverhalten frühzeitig zu stoppen.
- **Atomic Writes:** Modifikationen an Konfigurationsdateien sollen wenn möglich über temporäre Dateien ablaufen, die abschließend via `mv` ersetzt werden.
- **Kommentare:** Schreibe minimalen, aber klaren Code. "Was" passiert, steht im Code. "Warum" es hier steht, schreibst du in den Kommentar.

### Los geht's!
Hab keine Angst vor Fehlern. Wir lernen hier alle gemeinsam! Bei Fragen mach einfach ein GitHub Issue auf.
