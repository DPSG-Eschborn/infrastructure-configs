# 🏕️ Pfadfinder-Cloud (DPSG-Eschborn)

Gut Pfad! 👋 Du willst einen neuen Server für uns aufsetzen und hast nicht viel Erfahrung mit IT? Gar kein Problem. Hier ist die absolute "No-Brainer" Anleitung zum einfach Kopieren. Du musst nicht verstehen, was im Hintergrund abläuft.

---

## 🚀 SCHNELL-INSTALLATION (Lokaler Homeserver / Pi)

Folge diesen 3 simplen Schritten, wenn du Ubuntu am Laufen hast und vor dem schwarzen Fenster (Terminal) sitzt:

**Schritt 1:** Logge dich als Administrator ("root") ein. Kopiere den folgenden Befehl, drück Enter und gib dein Passwort ein (Achtung: beim Eintippen des Passworts werden keine Sterne angezeigt, einfach blind tippen und Enter drücken!):
```bash
sudo su -
```

**Schritt 2:** Lade unsere automatische Server-Einrichtung herunter und starte sie:
```bash
curl -sL https://raw.githubusercontent.com/DPSG-Eschborn/infrastructure-configs/main/bootstrap.sh -o /tmp/bootstrap.sh && bash /tmp/bootstrap.sh
```

**Schritt 3:** Das war's schon! Es öffnet sich nun ein Menü. Es fragt dich auf Deutsch, wie eure Gruppen-Domain heißt und welche Module du installieren willst (tippe `y` um zuzustimmen). Den schweren Rest, inklusive SSL-Zertifikaten (grünes Schloss) und sicheren Datenbank-Passwörtern bauen wir völlig unsichtbar im Hintergrund zusammen.

---

## ☁️ SCHNELL-INSTALLATION (Hetzner Cloud-Server)

Wenn du für den Stamm einen neuen großen Cloud-Server mietest, geht es sogar noch einfacher (ganz ohne Terminal!):

1. Gehe in den Ordner `cloud-configs` und öffne die Datei [`hetzner-basic-node.yaml`](./cloud-configs/hetzner-basic-node.yaml).
2. Kopiere dir den gigantischen englischen Textblock einfach raus.
3. Ändere unten im Text das `unsere-domain.de` (hinter `--domain=`) auf eure echte DPSG-Domain. (Und optional ganz oben den GitHub-Namen für deinen eigenen Fernzugriff).
4. Klicke bei Hetzner bei der Server-Erstellung auf den unscheinbaren Reiter "Cloud config" (oder "User Data") und füge den ganzen Text dort ein.
5. Klicke auf Server kaufen. 

**Fertig!** Du hast Pause. Der Server zimmert sich beim ersten Hochfahren innerhalb von 4 Minuten komplett von selbst zusammen. Er vernagelt die Firewall extrem sicher, installiert den Router (Traefik), lädt die Nextcloud und platziert die Homepage im Web. Alles automatisch verschlüsselt!

---

## 📚 Für die Nerds (Wie funktioniert das alles?)

Falls du tiefer einsteigen willst, um z.B. eine Kassen-Software zu ergänzen, gibt es eigene Fach-Erklärungen:
- [Wie funktioniert die Hetzner-Installation im Detail?](./docs/hetzner-installation.md)
- [Wie funktioniert das Homeserver-Setup im Detail?](./docs/homeserver-installation.md)
- [Wie verbinde ich eine Hetzner Storage Box?](./docs/storagebox-anbindung.md)
- [Architektur: Wie programmiere ich neue Plugins für das Setup-Menü?](./docs/plugin-entwicklung.md)
- [Wie kann ich meinen Code bei der DPSG pushen? (CONTRIBUTING)](./CONTRIBUTING.md)

*Viel Spaß und Gut Pfad!*
