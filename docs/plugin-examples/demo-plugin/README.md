# Das ultimative Demo-Plugin

Dieser Ordner (`docs/plugin-examples/demo-plugin`) ist eine Blaupause für Plugin-Entwickler. Er demonstriert die Architektur der **Pfadfinder-Cloud**.

Anstatt Kern-Logik im Setup-Skript hart zu verankern, stellt `setup.sh` eine "Orchestrierungs-Pipeline" zur Verfügung. Module können sich durch spezifische Dateinamen in bestimmte Phasen einklinken (Hooks).

Für die Entwicklung von Scripts ist es wichtig zu wissen, dass `setup.sh` die Scripts als Root ausführt. Hierfür gibt es gewisse Regeln, die beachtet werden müssen. Diese findest weiter unten in dieser Datei.

---

## 🔍 Wie Plugins "entdeckt" werden (Discovery)

Es gibt keine globale Liste aller Plugins. `setup.sh` sucht beim Start automatisch in den Ordnern `/core/*` und `/extensions/*` nach einer Datei namens `manifest.env`. Findet es diese Datei, liest es Metadaten (Name, Beschreibung) aus und fügt das Modul dynamisch dem interaktiven Auswahl-Menü hinzu.

Du brauchst für dein eigenes Modul als absolutes Minimum:

1. `manifest.env` (Pflicht für die Discovery)
2. `docker-compose.yml` UND/ODER `pre-deploy.sh` (Irgendetwas muss das Modul ja tun)

Alle anderen Skripte sind **100% optional**.

---

## ⏱️ Die Reihenfolge der Ausführung (Lifecycle)

Hat der Nutzer im Menü "Installieren" gewählt, durchläuft das Skript alle aktivierten Module in dieser exakten Reihenfolge:

1. **`validate.sh` (Validierung):**
   * *Aktion:* Prüft Abhängigkeiten (z.B. "Darf Modul A ohne Modul B installiert werden?").
   * *Ausgabe:* Bei `exit 1` entfernt sich das Modul selbst aus der Installation für diesen Durchlauf. Bei `exit 0` passiert nichts.

2. **`configure.sh` (Interaktive Nutzer-Abfrage):**
   * *Aktion:* Wird *nur* im interaktiven Modus gestartet. Stellt dem User Fragen (z.B. "Passwort eingeben").
   * *API:* Das Skript kann Variablen für die `.env` über eine temporäre Datei (`$MODULE_ENV_FILE`) exportieren.

3. **Env Generation *(Kein Skript, automatisch)*:**
   * `setup.sh` kopiert die `.env.example` und ersetzt Platzhalter wie `DOMAIN_PLACEHOLDER`, `PASSWORD_PLACEHOLDER` sowie die Variablen aus `configure.sh`.

4. **`pre-deploy.sh` (Host-Konfiguration):**
   * *Aktion:* Ausführung direkter Befehle auf dem Linux Host System *bevor* Container gestartet werden.
   * *Nutzung:* Festplatten partitionieren, Mounts erstellen (`/etc/fstab`), Cron-Jobs eintragen oder Fallback-Skripte anlegen.

5. **`docker-compose.yml` (Container Start):**
   * *Aktion:* Das Setup triggert einen klassischen `docker compose up -d` in dem Modul-Ordner.

6. **`post-deploy.sh` (Post-Konfiguration):**
   * *Aktion:* Ausführung auf dem Host, *nachdem* der App-Container läuft.
   * *Nutzung:* Initialen DB-Nutzer via API anlegen, Health-Checks oder Cleanup aufräumen.

---

## ⚠️  Regeln beim Schreiben der Skripte

Jedes Hook-Skript (egal ob `.sh`) wird von `setup.sh` direkt via `bash` als eigener Prozess aufgerufen. Dabei gibt es klare Pflicht-Kriterien für stabilen Code:

1. **Der Strict Mode:**
   Jedes Bash-Skript MUSS in der zweiten Zeile `set -euo pipefail` stehen haben. Das garantiert, dass unvorhersehbare Fehler, wie ein fehlgeschlagener `mkdir`, das Skript hart abbrechen, anstatt in defektem Zustand weiterzulaufen.

2. **Sauberes Error Handling:**
   Das `setup.sh` interpretiert die Exit Codes deiner Skripte. Laufen Befehle durch, gilt Exit 0 (Erfolg). Willst du bewusst abbrechen (z.B. in `validate.sh`), nutze explizit `exit 1`.

3. **Idempotenz (WICHTIG!):**
   Dein Skript muss zu 100% *idempotent* sein. Das bedeutet: Wenn jemand `setup.sh` 50x hintereinander ausführt, darf dein `pre-deploy.sh` das System nicht schrotten.

   * **Falsch:** `echo "123" >> /etc/fstab` (Erstellt bei 50 Läufen 50 duplizierte Zeilen).
   * **Richtig:** `grep -q "123" /etc/fstab || echo "123" >> /etc/fstab` (Prüft erst ob es da ist).

Schau dir die einzelnen Dateien in diesem Ordner an, sie sind alle logisch kommentiert!
