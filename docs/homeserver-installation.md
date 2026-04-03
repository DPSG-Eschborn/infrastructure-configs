# Self-Hosted / Homeserver Setup

Auf lokal gehosteten Servern (Mini-PCs, Raspberry Pi, lokale VMs) steht in der Regel kein Cloud-Init zur Verfügung. Die Initialisierung muss daher manuell ausgelöst werden.

## Manueller Bootstrapping-Prozess

Um den initialen Aufwand zu minimieren, wird ein Einzeilen-Skript (One-Liner) verwendet. Das Zielsystem muss lediglich über eine lauffähige Ubuntu 24.04 Installation und eine Internetverbindung verfügen. Vorabinstallationen von Werkzeugen wie Docker sind nicht erforderlich.

### Ablauf
1. Ubuntu 24.04 auf dem Zielsystem (Homeserver / Pi) installieren.
2. Ein initialer Login über SSH oder das direkte Terminal am Gerät ist erforderlich.
3. Du benötigst Root-Rechte. Werde Root (z.B. durch Eingabe von `sudo su` und deinem Passwort) und führe dann den folgenden Befehl aus:

   ```bash
   bash <(curl -sL https://raw.githubusercontent.com/DPSG-Eschborn/infrastructure-configs/main/bootstrap.sh)
   ```

### Funktionsweise des Bootstrap-Skripts
Der Befehl lädt die Datei `bootstrap.sh` herunter und führt sie direkt aus. Dieses Skript übernimmt die Basis-Initialisierung:

1. **Abhängigkeiten:** Grundlegende Werkzeuge wie `git` und `curl` werden installiert.
2. **Repository klonen:** Das Repository wird in das Zielverzeichnis `/opt/pfadfinder-cloud/` geklont.
3. **Setup-Aufruf:** Das interaktive Menü des Hauptskripts wird gestartet (`/opt/pfadfinder-cloud/setup.sh --interactive`).

Das `setup.sh` Skript verarbeitet anschließend die weitere Installation, richtet Docker ein und erfragt die gewünschten Module via Terminal-Dialog.

---

## Ausfallsicherheit des Bootstrappings

Das `bootstrap.sh` Skript ist nach P10-Standards gehärtet, um Netzwerkabbrüche oder unvorhergesehene Fehler zu handhaben:

1. **Strict Mode (`set -euo pipefail`):** Fehlende Variablen oder fehlschlagende Befehle führen zum sofortigen und sicheren Abbruch des Skripts.
2. **Keine imperfekten Downloads:** Die Syntax `bash <(...)` leitet den Code nicht zeilenweise in die Laufzeitumgebung (wie bei `| bash`), sondern stellt sicher, dass das Skript vollständig geladen wurde, bevor es interpretiert wird.
3. **Idempotenz:** Bei wiederholter Ausführung erkennt das Skript, dass `/opt/pfadfinder-cloud` bereits existiert. Statt eines erneuten Klons oder der Beschädigung lokaler Zustände wird ein sicherer Git-Reset durchgeführt, um den aktuellen Main-Branch wiederherzustellen.
