#Requires -Version 5.1
<#
.SYNOPSIS
    Pfadfinder-Cloud Setup-Assistent (Windows)
.DESCRIPTION
    Provider-agnostischer Setup-Wizard fuer die Pfadfinder-Cloud Infrastruktur.
    Unterstuetzte Provider: Hetzner Cloud (API), Remote-Server (SSH), Lokal.
    Erfordert keine zusaetzlichen Installationen — nutzt nur eingebaute Windows-Tools.
.NOTES
    Ausfuehrung: Doppelklick auf deploy.bat oder:
    powershell -ExecutionPolicy Bypass -File deploy.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ╔════════════════════════════════════════════════════════════════════╗
# ║                        KONFIGURATION                              ║
# ╚════════════════════════════════════════════════════════════════════╝

$Script:REPO_URL      = "https://github.com/DPSG-Eschborn/infrastructure-configs.git"
$Script:BOOTSTRAP_URL = "https://raw.githubusercontent.com/DPSG-Eschborn/infrastructure-configs/main/bootstrap.sh"
$Script:HETZNER_API   = "https://api.hetzner.cloud/v1"
$Script:SERVER_TYPE   = "cx22"
$Script:SERVER_IMAGE  = "ubuntu-24.04"
$Script:SERVER_LOCATION = "fsn1"

# ╔════════════════════════════════════════════════════════════════════╗
# ║                       UI-HILFSFUNKTIONEN                          ║
# ╚════════════════════════════════════════════════════════════════════╝

function Write-Color {
    param(
        [string]$Text,
        [ConsoleColor]$Color = "White",
        [switch]$NoNewline
    )
    $params = @{ Object = $Text; ForegroundColor = $Color }
    if ($NoNewline) { $params.NoNewLine = $true }
    Write-Host @params
}

function Write-Banner {
    param([string]$Title, [string[]]$Lines)
    $width = 56
    Write-Host ""
    Write-Color ("=" * $width) Cyan
    Write-Color ("   $Title") Cyan
    Write-Color ("=" * $width) Cyan
    foreach ($line in $Lines) {
        Write-Host "  $line"
    }
    Write-Color ("=" * $width) Cyan
    Write-Host ""
}

function Write-Step {
    param([int]$Current, [int]$Total, [string]$Description)
    Write-Host ""
    Write-Color "--- Schritt $Current/$Total : $Description ---" Yellow
    Write-Host ""
}

function Write-Success { param([string]$Text) Write-Color "[OK] $Text" Green }
function Write-Warn    { param([string]$Text) Write-Color "[!]  $Text" Yellow }
function Write-Err     { param([string]$Text) Write-Color "[X]  $Text" Red }
function Write-Info    { param([string]$Text) Write-Color "[-]  $Text" Cyan }

function Read-Choice {
    param(
        [string]$Prompt,
        [string[]]$ValidChoices,
        [string]$Default = ""
    )
    while ($true) {
        $displayPrompt = $Prompt
        if ($Default) { $displayPrompt += " [$Default]" }
        Write-Host "$displayPrompt : " -NoNewline
        $input_val = Read-Host
        if ([string]::IsNullOrWhiteSpace($input_val) -and $Default) {
            return $Default
        }
        if ($input_val -in $ValidChoices) {
            return $input_val
        }
        Write-Warn "Ungueltige Eingabe. Erlaubt: $($ValidChoices -join ', ')"
    }
}

function Read-SecureInput {
    param([string]$Prompt)
    Write-Host "$Prompt : " -NoNewline
    $secure = Read-Host -AsSecureString
    # SecureString -> Plaintext (noetig fuer SSH/API Uebergabe)
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Read-YesNo {
    param([string]$Prompt, [bool]$Default = $true)
    $hint = if ($Default) { "J/n" } else { "j/N" }
    Write-Host "$Prompt ($hint): " -NoNewline
    $input_val = Read-Host
    if ([string]::IsNullOrWhiteSpace($input_val)) { return $Default }
    return ($input_val -match '^[jJyY]')
}

# ╔════════════════════════════════════════════════════════════════════╗
# ║                       INPUT-VALIDIERUNG                           ║
# ╚════════════════════════════════════════════════════════════════════╝

function Test-IPv4Address {
    param([string]$IP)
    if ($IP -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
        $octets = $IP -split '\.'
        foreach ($octet in $octets) {
            $num = [int]$octet
            if ($num -lt 0 -or $num -gt 255) { return $false }
        }
        return $true
    }
    return $false
}

function Test-DomainName {
    param([string]$Domain)
    # RFC 1035 konform: Buchstaben, Zahlen, Bindestriche, Punkte
    return ($Domain -match '^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$')
}

function Test-SSHAvailable {
    $sshPath = Get-Command "ssh.exe" -ErrorAction SilentlyContinue
    return ($null -ne $sshPath)
}

function Test-HetznerToken {
    param([string]$Token)
    try {
        $headers = @{
            "Authorization" = "Bearer $Token"
            "Content-Type"  = "application/json"
        }
        # Leichtgewichtiger API-Test: SSH-Keys auflisten
        $null = Invoke-RestMethod -Uri "$Script:HETZNER_API/ssh_keys" `
            -Method Get -Headers $headers -TimeoutSec 10
        return $true
    } catch {
        return $false
    }
}

# ╔════════════════════════════════════════════════════════════════════╗
# ║                    KONFIGURATIONS-SAMMLUNG                        ║
# ╚════════════════════════════════════════════════════════════════════╝

function Get-ProviderChoice {
    Write-Banner "Pfadfinder-Cloud Setup-Assistent" @(
        "",
        "Willkommen! Dieses Skript richtet euren",
        "Pfadfinder-Server vollautomatisch ein.",
        "",
        "[1] Hetzner Cloud",
        "    (Wir erstellen den Server fuer euch!)",
        "",
        "[2] Eigener Server / anderer Anbieter",
        "    (Ihr habt schon einen Server mit IP)",
        "",
        "[3] Dieser Computer hier",
        "    (Fuer lokale Homeserver / Raspberry Pi)",
        ""
    )
    return Read-Choice "Deine Wahl" @("1","2","3")
}

function Get-HetznerConfig {
    Write-Step 1 4 "Hetzner Cloud Zugangsdaten"

    Write-Host "  Fuer die automatische Server-Erstellung brauchen wir"
    Write-Host "  deinen Hetzner Cloud API-Token. So bekommst du ihn:"
    Write-Host ""
    Write-Host "    1. Gehe auf https://console.hetzner.cloud"
    Write-Host "    2. Waehle dein Projekt (oder erstelle eins)"
    Write-Host "    3. Klicke links auf 'Sicherheit' > 'API-Tokens'"
    Write-Host "    4. Klicke 'API-Token generieren'"
    Write-Host "    5. Name: 'pfadfinder-setup'"
    Write-Host "       Berechtigung: 'Lesen & Schreiben'"
    Write-Host ""

    $token = ""
    while ($true) {
        $token = Read-SecureInput "Dein API-Token"
        if ([string]::IsNullOrWhiteSpace($token)) {
            Write-Warn "Kein Token eingegeben."
            continue
        }
        Write-Info "Pruefe Token bei Hetzner..."
        if (Test-HetznerToken $token) {
            Write-Success "API-Token gueltig!"
            break
        } else {
            Write-Err "Token ungueltig oder Hetzner nicht erreichbar. Nochmal versuchen."
        }
    }

    Write-Host ""
    Write-Host "  Optional: GitHub-Username fuer SSH-Zugang zum Server."
    Write-Host "  (Dein oeffentlicher SSH-Key wird automatisch importiert.)"
    Write-Host "  Leer lassen = nur Root-Passwort Zugang."
    Write-Host ""
    Write-Host "GitHub Username (optional): " -NoNewline
    $ghUser = Read-Host

    return @{
        Token      = $token
        GitHubUser = $ghUser
    }
}

function Get-SSHConfig {
    Write-Step 1 4 "Server-Verbindungsdaten"

    if (-not (Test-SSHAvailable)) {
        Write-Err "SSH ist auf diesem Windows nicht verfuegbar!"
        Write-Host ""
        Write-Host "  So aktivierst du es:"
        Write-Host "  1. Oeffne 'Einstellungen' > 'Apps' > 'Optionale Features'"
        Write-Host "  2. Klicke 'Feature hinzufuegen'"
        Write-Host "  3. Suche nach 'OpenSSH-Client' und installiere es"
        Write-Host "  4. Starte diesen Assistenten neu"
        Write-Host ""
        throw "SSH-Client nicht verfuegbar. Bitte installiere den OpenSSH-Client."
    }

    Write-Success "SSH-Client gefunden."
    Write-Host ""

    # IP-Adresse
    $ip = ""
    while ($true) {
        Write-Host "IP-Adresse deines Servers: " -NoNewline
        $ip = Read-Host
        if (Test-IPv4Address $ip) {
            break
        }
        Write-Warn "Ungueltige IP-Adresse. Format: z.B. 123.45.67.89"
    }

    # SSH-Port
    $port = Read-Choice "SSH-Port" @("22","2222","2200","23") "22"

    return @{
        IP   = $ip
        Port = $port
    }
}

function Get-DeploymentConfig {
    Write-Step 2 4 "Konfiguration"

    # --- Domain ---
    Write-Host "  Habt ihr schon eine Domain (z.B. dpsg-muster.de)?"
    Write-Host "  Falls nicht, einfach leer lassen - dann nutzen wir"
    Write-Host "  einen Testmodus der auch ohne Domain funktioniert."
    Write-Host "  (Ihr koennt die Domain spaeter jederzeit aendern.)"
    Write-Host ""

    $domain = ""
    while ($true) {
        Write-Host "Eure Domain (leer = Testmodus): " -NoNewline
        $input_val = Read-Host
        if ([string]::IsNullOrWhiteSpace($input_val)) {
            $domain = "AUTO"
            Write-Info "Testmodus: Server wird ueber IP erreichbar sein (HTTP)."
            break
        }
        if (Test-DomainName $input_val) {
            $domain = $input_val
            Write-Success "Domain: $domain"
            break
        }
        Write-Warn "Ungueltige Domain. Beispiel: dpsg-muster.de"
    }
    Write-Host ""

    # --- Module ---
    Write-Host "  Welche Dienste sollen installiert werden?"
    Write-Host ""

    $modules = @("core")  # Core (Traefik) ist immer dabei
    Write-Color "  [*] Traefik (Reverse Proxy) - immer aktiv" DarkGray

    if (Read-YesNo "  Nextcloud installieren? (empfohlen)" $true) {
        $modules += "nextcloud"
    }
    if (Read-YesNo "  Stammes-Website installieren?" $false) {
        $modules += "website"
    }

    # --- Storage Box ---
    $storageBox = $null
    if ("nextcloud" -in $modules) {
        Write-Host ""
        Write-Host "  Habt ihr eine Hetzner Storage Box als Speicher?"
        Write-Host "  (Guenstiger Massenspeicher fuer Nextcloud-Dateien)"
        Write-Host ""
        if (Read-YesNo "  Hetzner Storage Box einbinden?" $false) {
            Write-Host ""
            Write-Warn "WICHTIG: SMB muss in der Hetzner Console aktiviert sein!"
            Write-Host "  (Hetzner Console > Storage Box > Einstellungen > Samba)"
            Write-Host ""

            $sbUser = ""
            while ($true) {
                Write-Host "  Storage Box Username (z.B. u123456): " -NoNewline
                $sbUser = Read-Host
                if ($sbUser -match '^u\d+(-sub\d+)?$') {
                    break
                }
                Write-Warn "Format: u123456 oder u123456-sub1"
            }
            $sbPass = Read-SecureInput "  Storage Box Passwort"

            if (-not [string]::IsNullOrWhiteSpace($sbPass)) {
                $modules += "storagebox"
                $storageBox = @{ User = $sbUser; Pass = $sbPass }
                Write-Success "Storage Box konfiguriert."
            } else {
                Write-Warn "Kein Passwort eingegeben. Storage Box wird uebersprungen."
            }
        }
    }
    Write-Host ""

    return @{
        Domain     = $domain
        Modules    = $modules
        StorageBox = $storageBox
    }
}

function Show-Summary {
    param(
        [string]$ProviderName,
        [hashtable]$DeployConfig
    )
    $modulesStr = $DeployConfig.Modules -join ", "
    $domainStr = if ($DeployConfig.Domain -eq "AUTO") { "Testmodus (IP)" } else { $DeployConfig.Domain }
    $sbStr = if ($DeployConfig.StorageBox) { "$($DeployConfig.StorageBox.User) (aktiv)" } else { "nicht konfiguriert" }

    Write-Banner "Zusammenfassung" @(
        "",
        "Provider:    $ProviderName",
        "Domain:      $domainStr",
        "Module:      $modulesStr",
        "Storage Box: $sbStr",
        ""
    )
}

# ╔════════════════════════════════════════════════════════════════════╗
# ║                     PROVIDER-IMPLEMENTIERUNGEN                    ║
# ╚════════════════════════════════════════════════════════════════════╝

function Build-SetupArgs {
    param([hashtable]$Config)
    # Baut die Kommandozeilen-Argumente fuer setup.sh
    $args_list = @(
        "--headless"
        "--install=$($Config.Modules -join ',')"
        "--domain=$($Config.Domain)"
    )
    if ($Config.StorageBox) {
        $args_list += "--storagebox-user=$($Config.StorageBox.User)"
        $args_list += "--storagebox-pass=$($Config.StorageBox.Pass)"
    }
    return $args_list
}

function Build-CloudInitYaml {
    param(
        [hashtable]$DeployConfig,
        [string]$GitHubUser = ""
    )
    $setupArgs = (Build-SetupArgs $DeployConfig) -join " "

    # SSH-Key Block (optional)
    $sshBlock = ""
    if (-not [string]::IsNullOrWhiteSpace($GitHubUser)) {
        $sshBlock = @"

  - name: pfadiadmin
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - gh:$GitHubUser
"@
    } else {
        $sshBlock = @"

  - name: pfadiadmin
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
"@
    }

    $yaml = @"
#cloud-config
users:$sshBlock

package_update: true
package_upgrade: true
packages:
  - git
  - curl
  - openssl

runcmd:
  - git clone $($Script:REPO_URL) /opt/pfadfinder-cloud
  - cd /opt/pfadfinder-cloud && chmod +x setup.sh && ./setup.sh $setupArgs > /var/log/pfadfinder-setup.log 2>&1
  - usermod -aG docker pfadiadmin
"@
    return $yaml
}

function Invoke-HetznerDeploy {
    param(
        [hashtable]$HetznerConfig,
        [hashtable]$DeployConfig
    )
    Write-Step 4 4 "Server erstellen"
    Write-Info "Generiere Cloud-Init Konfiguration..."

    $cloudInit = Build-CloudInitYaml -DeployConfig $DeployConfig -GitHubUser $HetznerConfig.GitHubUser

    $body = @{
        name             = "pfadfinder-cloud"
        server_type      = $Script:SERVER_TYPE
        image            = $Script:SERVER_IMAGE
        location         = $Script:SERVER_LOCATION
        start_after_create = $true
        user_data        = $cloudInit
    } | ConvertTo-Json -Depth 10

    $headers = @{
        "Authorization" = "Bearer $($HetznerConfig.Token)"
        "Content-Type"  = "application/json"
    }

    Write-Info "Erstelle Server bei Hetzner ($Script:SERVER_TYPE in $Script:SERVER_LOCATION)..."

    try {
        $response = Invoke-RestMethod -Uri "$Script:HETZNER_API/servers" `
            -Method Post -Headers $headers -Body $body -TimeoutSec 30
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 422) {
            Write-Err "Server-Name 'pfadfinder-cloud' existiert bereits in diesem Projekt."
            Write-Host "  Loesung: Loesche den alten Server in der Hetzner Console oder waehle einen anderen Namen."
        } elseif ($statusCode -eq 403) {
            Write-Err "Keine Berechtigung. Ist der Token auf 'Lesen & Schreiben' gesetzt?"
        } else {
            Write-Err "Hetzner API Fehler: $_"
        }
        throw "Server-Erstellung fehlgeschlagen."
    }

    $serverIP = $response.server.public_net.ipv4.ip
    $rootPassword = $response.root_password
    $serverID = $response.server.id

    Write-Success "Server erstellt! (ID: $serverID)"
    Write-Host ""

    # Warten bis Server laeuft
    Write-Info "Warte bis Server bereit ist..."
    $maxAttempts = 30
    for ($i = 1; $i -le $maxAttempts; $i++) {
        Start-Sleep -Seconds 5
        try {
            $status = Invoke-RestMethod -Uri "$Script:HETZNER_API/servers/$serverID" `
                -Method Get -Headers $headers -TimeoutSec 10
            if ($status.server.status -eq "running") {
                Write-Success "Server laeuft!"
                break
            }
            Write-Host "  Status: $($status.server.status) ... ($i/$maxAttempts)" -NoNewline:$false
        } catch {
            # Netzwerkfehler ignorieren, weiter versuchen
        }
        if ($i -eq $maxAttempts) {
            Write-Warn "Timeout beim Warten. Server wird trotzdem eingerichtet."
        }
    }

    return @{
        IP           = $serverIP
        RootPassword = $rootPassword
    }
}

function Invoke-SSHDeploy {
    param(
        [hashtable]$SSHConfig,
        [hashtable]$DeployConfig
    )
    Write-Step 4 4 "Server einrichten"

    $ip = $SSHConfig.IP
    $port = $SSHConfig.Port
    $setupArgs = (Build-SetupArgs $DeployConfig) -join " "

    # Einzeiliger Remote-Befehl: Bootstrap + Setup
    $remoteCommand = "curl -sL $($Script:BOOTSTRAP_URL) -o /tmp/bootstrap.sh && bash /tmp/bootstrap.sh $setupArgs"

    # Base64-Kodierung um Shell-Escaping-Probleme zu vermeiden
    # (Schuetzt Sonderzeichen in Passwoertern vor Shell-Interpretation)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($remoteCommand)
    $b64 = [Convert]::ToBase64String($bytes)

    Write-Info "Verbinde mit $ip (Port $port)..."
    Write-Host ""
    Write-Warn "Du wirst gleich nach dem Root-Passwort gefragt."
    Write-Host "  (Das ist das Passwort deines Servers, nicht dein Windows-Passwort!)"
    Write-Host ""

    # Einzige SSH-Verbindung — ein Passwort-Eingabe reicht
    $sshArgs = @(
        "-o", "StrictHostKeyChecking=accept-new"
        "-o", "ConnectTimeout=15"
        "-p", $port
        "root@$ip"
        "echo $b64 | base64 -d | bash"
    )

    Write-Info "Starte Einrichtung (das dauert 3-5 Minuten)..."
    Write-Host ""
    & ssh @sshArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Err "SSH-Verbindung fehlgeschlagen (Exit-Code: $LASTEXITCODE)."
        Write-Host ""
        Write-Host "  Moegliche Ursachen:"
        Write-Host "  - IP-Adresse oder Passwort falsch"
        Write-Host "  - Server ist nicht erreichbar (Firewall?)"
        Write-Host "  - SSH-Port stimmt nicht (Standard: 22)"
        throw "SSH-Deployment fehlgeschlagen."
    }

    return @{ IP = $ip }
}

function Invoke-LocalDeploy {
    param([hashtable]$DeployConfig)
    Write-Step 4 4 "Lokale Einrichtung"

    Write-Info "Pruefe Betriebssystem..."
    if ($IsLinux -or (Test-Path "/etc/os-release")) {
        $setupArgs = (Build-SetupArgs $DeployConfig) -join " "
        $cmd = "curl -sL $($Script:BOOTSTRAP_URL) -o /tmp/bootstrap.sh && bash /tmp/bootstrap.sh $setupArgs"
        Write-Info "Starte bootstrap.sh..."
        & bash -c $cmd
    } else {
        Write-Warn "Lokale Installation ist nur auf Linux-Systemen moeglich."
        Write-Host ""
        Write-Host "  Du bist auf Windows. Nutze stattdessen:"
        Write-Host "  - Option [1] (Hetzner Cloud) — Server wird automatisch erstellt"
        Write-Host "  - Option [2] (Eigener Server) — SSH-Verbindung zu deinem Linux-Server"
        throw "Lokale Installation nur unter Linux moeglich."
    }

    # IP des lokalen Systems ermitteln
    $localIP = "localhost"
    try {
        $localIP = (curl -4 -s icanhazip.com 2>$null)
    } catch { }
    return @{ IP = $localIP }
}

# ╔════════════════════════════════════════════════════════════════════╗
# ║                       ERGEBNIS-ANZEIGE                            ║
# ╚════════════════════════════════════════════════════════════════════╝

function Show-Result {
    param(
        [hashtable]$DeployConfig,
        [hashtable]$Result,
        [string]$ProviderType
    )
    $ip = $Result.IP
    $domain = $DeployConfig.Domain
    $isTestMode = ($domain -eq "AUTO")

    if ($isTestMode) {
        $ncUrl  = "http://cloud.${ip}.nip.io"
        $wwwUrl = "http://www.${ip}.nip.io"
    } else {
        $ncUrl  = "https://cloud.$domain"
        $wwwUrl = "https://www.$domain"
    }

    $lines = @(
        "",
        "Euer Server wird jetzt eingerichtet!",
        "(Die Einrichtung dauert ca. 3-5 Minuten.)",
        ""
    )

    if ("nextcloud" -in $DeployConfig.Modules) {
        $lines += "Nextcloud: $ncUrl"
    }
    if ("website" -in $DeployConfig.Modules) {
        $lines += "Website:   $wwwUrl"
    }

    $lines += ""
    $lines += "Server-IP: $ip"

    if ($Result.RootPassword) {
        $lines += ""
        $lines += "Root-Passwort: $($Result.RootPassword)"
        $lines += "(SICHER AUFBEWAHREN! Wird nur einmal angezeigt!)"
    }

    if (-not $isTestMode) {
        $lines += ""
        $lines += "WICHTIG: DNS-Eintraege setzen!"
        $lines += "Erstellt bei eurem Domain-Anbieter A-Records:"
        if ("nextcloud" -in $DeployConfig.Modules) {
            $lines += "  cloud -> $ip"
        }
        if ("website" -in $DeployConfig.Modules) {
            $lines += "  www   -> $ip"
        }
    }
    $lines += ""

    Write-Banner "Fertig!" $lines

    if ($ProviderType -eq "hetzner") {
        Write-Host ""
        Write-Color "  Hinweis: Der Server richtet sich im Hintergrund selbst ein." Yellow
        Write-Color "  Warte ca. 3-5 Minuten, dann sind die Dienste erreichbar." Yellow
        Write-Host ""
    }
}

# ╔════════════════════════════════════════════════════════════════════╗
# ║                          HAUPTPROGRAMM                            ║
# ╚════════════════════════════════════════════════════════════════════╝

function Start-Wizard {
    # Schritt 1: Provider-Auswahl
    $providerChoice = Get-ProviderChoice

    $providerConfig = $null
    $providerName = ""
    $providerType = ""

    switch ($providerChoice) {
        "1" {
            $providerName = "Hetzner Cloud ($Script:SERVER_TYPE, $Script:SERVER_LOCATION)"
            $providerType = "hetzner"
            $providerConfig = Get-HetznerConfig
        }
        "2" {
            $providerName = "Eigener Server (SSH)"
            $providerType = "ssh"
            $providerConfig = Get-SSHConfig
        }
        "3" {
            $providerName = "Lokale Installation"
            $providerType = "local"
            $providerConfig = @{}
        }
    }

    # Schritt 2: Konfiguration (provider-agnostisch)
    $deployConfig = Get-DeploymentConfig

    # Schritt 3: Zusammenfassung + Bestaetigung
    Show-Summary $providerName $deployConfig

    if (-not (Read-YesNo "Alles korrekt? Einrichtung starten?" $true)) {
        Write-Warn "Abgebrochen."
        return
    }

    # Schritt 4: Deployment (provider-spezifisch)
    $result = $null
    switch ($providerType) {
        "hetzner" { $result = Invoke-HetznerDeploy $providerConfig $deployConfig }
        "ssh"     { $result = Invoke-SSHDeploy $providerConfig $deployConfig }
        "local"   { $result = Invoke-LocalDeploy $deployConfig }
    }

    # Schritt 5: Ergebnis
    Show-Result $deployConfig $result $providerType
}

# ╔════════════════════════════════════════════════════════════════════╗
# ║                          ENTRY POINT                              ║
# ╚════════════════════════════════════════════════════════════════════╝

try {
    Start-Wizard
} catch {
    Write-Host ""
    Write-Err "Ein Fehler ist aufgetreten:"
    Write-Host ""
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Falls du Hilfe brauchst, oeffne ein Issue auf GitHub:"
    Write-Host "  $Script:REPO_URL" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}
