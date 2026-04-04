# 🏕️ Pfadfinder-Cloud (DPSG-Eschborn)

Gut Pfad! 👋 Du willst einen neuen Server für uns aufsetzen und hast nicht viel Erfahrung mit IT? Gar kein Problem. Hier ist die absolute "No-Brainer" Anleitung zum einfach Kopieren. Du musst nicht verstehen, was im Hintergrund abläuft.

---

## 🎯 DER EINFACHSTE WEG (0 Vorkenntnisse nötig)

### Windows

**Option A** — Datei herunterladen:

1. Lade [`deploy.bat`](https://raw.githubusercontent.com/DPSG-Eschborn/infrastructure-configs/main/deploy.bat) herunter (Rechtsklick → *Ziel speichern unter...*)
2. Doppelklicke auf die Datei — der Assistent startet automatisch!

**Option B** — PowerShell-Befehl (Rechtsklick auf Start → *Terminal*):

```powershell
irm https://raw.githubusercontent.com/DPSG-Eschborn/infrastructure-configs/main/deploy.ps1 -OutFile $env:TEMP\deploy.ps1; & $env:TEMP\deploy.ps1
```

### Linux / macOS

Öffne ein Terminal und führe diesen einen Befehl aus:

```bash
curl -sL https://raw.githubusercontent.com/DPSG-Eschborn/infrastructure-configs/main/deploy.sh -o /tmp/deploy.sh && bash /tmp/deploy.sh
```

### Was kann der Assistent?

Der Assistent kann:

- Einen **neuen Hetzner-Server** automatisch für euch erstellen (nur API-Token nötig)
- Einen **bestehenden Server** per SSH einrichten (nur IP-Adresse + Passwort nötig)
- Einen **lokalen Homeserver** direkt konfigurieren

---

## 🚀 SCHNELL-INSTALLATION (Lokaler Homeserver / Pi)

Falls du lieber manuell am Terminal arbeitest (Ubuntu/Debian):

**Schritt 1:** Logge dich als Administrator ("root") ein:

```bash
sudo su -
```

**Schritt 2:** Lade unsere automatische Server-Einrichtung herunter und starte sie:

```bash
curl -sL https://raw.githubusercontent.com/DPSG-Eschborn/infrastructure-configs/main/bootstrap.sh -o /tmp/bootstrap.sh && bash /tmp/bootstrap.sh
```

**Schritt 3:** Das war's schon! Es öffnet sich nun ein Menü. Es fragt dich auf Deutsch, wie eure Gruppen-Domain heißt und welche Module du installieren willst (tippe `y` um zuzustimmen). Den schweren Rest, inklusive SSL-Zertifikaten (grünes Schloss) und sicheren Datenbank-Passwörtern bauen wir völlig unsichtbar im Hintergrund zusammen.

---

## ☁️ SCHNELL-INSTALLATION (Hetzner Cloud-Server — manuell)

Wenn du bei Hetzner ohne den Assistenten arbeiten willst:

1. Gehe in den Ordner `cloud-configs` und öffne die Datei [`hetzner-basic-node.yaml`](./cloud-configs/hetzner-basic-node.yaml).
2. Kopiere dir den Textblock einfach raus.
3. Optional: Ändere `--domain=AUTO` auf eure echte Domain (z.B. `--domain=dpsg-muster.de`).
4. Klicke bei Hetzner bei der Server-Erstellung auf den Reiter "Cloud config" und füge den Text dort ein.
5. Klicke auf Server kaufen.

**Fertig!** Der Server zimmert sich beim ersten Hochfahren innerhalb von 4 Minuten komplett von selbst zusammen.

---

## 📚 Für die Nerds (Wie funktioniert das alles?)

Falls du tiefer einsteigen willst, um z.B. eine Kassen-Software zu ergänzen, gibt es eigene Fach-Erklärungen:

- [Architektur & User-Flow: Wie funktioniert das Ganze?](./docs/architektur-uebersicht.md)
- [Wie funktioniert die Hetzner-Installation im Detail?](./docs/hetzner-installation.md)
- [Wie funktioniert das Homeserver-Setup im Detail?](./docs/homeserver-installation.md)
- [Wie verbinde ich eine Hetzner Storage Box?](./docs/storagebox-anbindung.md)
- [Architektur: Wie programmiere ich neue Plugins für das Setup-Menü?](./docs/plugin-entwicklung.md)
- [Wie kann ich meinen Code bei der DPSG pushen? (CONTRIBUTING)](./CONTRIBUTING.md)

*Viel Spaß und Gut Pfad!*
