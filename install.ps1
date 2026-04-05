#Requires -Version 5.1
<#
.SYNOPSIS
    Pfadfinder-Cloud Setup-Assistent (Windows)
.DESCRIPTION
    Provider-agnostischer Setup-Wizard fuer die Pfadfinder-Cloud Infrastruktur.
    Erstellt den Server (Hetzner) oder bereitet ihn vor (SSH/Local) und
    oeffnet anschliessend eine SSH-Bridge zum interaktiven Setup-Skript.
.NOTES
    Ausfuehrung: Doppelklick auf install.bat oder:
    powershell -ExecutionPolicy Bypass -File install.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Alte PowerShell-Versionen (z.B. v5.1 unter Windows Server) nutzen nicht zwingend TLS 1.2.
# Dies fuehrt zu Problemen bei REST-Aufrufen gegenueber modernen APIs wie Hetzner.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ╔════════════════════════════════════════════════════════════════════╗
# ║                        KONFIGURATION                              ║
# ╚════════════════════════════════════════════════════════════════════╝

$Script:REPO_URL      = "https://github.com/DPSG-Eschborn/infrastructure-configs.git"
$Script:BOOTSTRAP_URL = "https://raw.githubusercontent.com/DPSG-Eschborn/infrastructure-configs/main/engine/bootstrap.sh"
$Script:HETZNER_API   = "https://api.hetzner.cloud/v1"
$Script:SERVER_TYPE   = "cx22"
$Script:SERVER_IMAGE  = "ubuntu-24.04"
$Script:SERVER_LOCATION = "fsn1"

# ╔════════════════════════════════════════════════════════════════════╗
# ║                       UI-HILFSFUNKTIONEN                          ║
# ╚════════════════════════════════════════════════════════════════════╝

function Write-Color {
    param([string]$Text, [ConsoleColor]$Color = "White", [switch]$NoNewline)
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
    param([string]$Prompt, [string[]]$ValidChoices, [string]$Default = "")
    while ($true) {
        $displayPrompt = $Prompt
        if ($Default) { $displayPrompt += " [$Default]" }
        Write-Host "$displayPrompt : " -NoNewline
        $input_val = Read-Host
        if ([string]::IsNullOrWhiteSpace($input_val) -and $Default) { return $Default }
        if ($input_val -in $ValidChoices) { return $input_val }
        Write-Warn "Ungueltige Eingabe. Erlaubt: $($ValidChoices -join ', ')"
    }
}

function Read-SecureInput {
    param([string]$Prompt)
    Write-Host "$Prompt : " -NoNewline
    $secure = Read-Host -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    } finally {
        $null = [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
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
        $null = Invoke-RestMethod -Uri "$Script:HETZNER_API/ssh_keys" -Method Get -Headers $headers -TimeoutSec 10
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
        "Dieses Skript bereitet deinen Server auf das Deployment vor.",
        "Danach startest du automatisch in das Setup-Menue.",
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
    Write-Step 1 2 "Hetzner Cloud Zugangsdaten"

    Write-Host "  Gehe auf console.hetzner.cloud > Dein Projekt > Sicherheit > API-Tokens"
    Write-Host "  Generiere ein neues Token mit Berechtigung: 'Lesen & Schreiben'"
    Write-Host ""

    $token = ""
    while ($true) {
        $token = Read-SecureInput "Dein API-Token"
        if ([string]::IsNullOrWhiteSpace($token)) { continue }
        Write-Info "Pruefe Token bei Hetzner..."
        if (Test-HetznerToken $token) {
            Write-Success "API-Token gueltig!"
            break
        } else {
            Write-Err "Token ungueltig oder Hetzner nicht erreichbar. Nochmal versuchen."
        }
    }

    Write-Host ""
    Write-Host "  Optional: GitHub-Username fuer dauerhaften SSH-Zugang zum Server."
    Write-Host "  (Dein oeffentlicher SSH-Key wird automatisch importiert.)"
    Write-Host "GitHub Username: " -NoNewline
    $ghUser = Read-Host

    return @{
        Token      = $token
        GitHubUser = $ghUser
    }
}

function Get-SSHConfig {
    Write-Step 1 2 "Server-Verbindungsdaten"

    if (-not (Test-SSHAvailable)) {
        Write-Err "SSH ist auf diesem Windows nicht verfuegbar!"
        Write-Host "  Bitte installiere den 'OpenSSH-Client' (Optionale Features)."
        throw "SSH-Client nicht verfuegbar."
    }

    $ip = ""
    while ($true) {
        Write-Host "IP-Adresse deines Servers: " -NoNewline
        $ip = Read-Host
        if (Test-IPv4Address $ip) { break }
        Write-Warn "Ungueltige IP-Adresse."
    }

    $port = ""
    while ($true) {
        Write-Host "SSH-Port [22]: " -NoNewline
        $port = Read-Host
        if ([string]::IsNullOrWhiteSpace($port)) { $port = "22"; break }
        if ($port -match '^\d{1,5}$') { break }
    }

    return @{ IP = $ip; Port = $port }
}

# ╔════════════════════════════════════════════════════════════════════╗
# ║                     PROVIDER-IMPLEMENTIERUNGEN                    ║
# ╚════════════════════════════════════════════════════════════════════╝

function New-EphemeralKey {
    Write-Info "Generiere temporaeren SSH-Schluessel fuer das Setup..."
    $sshDir = Join-Path $env:USERPROFILE ".ssh"
    if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }
    
    $keyFile = Join-Path $sshDir "pfadi_setup_key_tmp"
    if (Test-Path $keyFile) { Remove-Item $keyFile -Force }
    if (Test-Path "$keyFile.pub") { Remove-Item "$keyFile.pub" -Force }

    # Generate key quietly
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "ssh-keygen.exe"
    $pinfo.Arguments = "-t ed25519 -N `"`" -C `"ephemeral_pfadi_key`" -f `"$keyFile`" -q"
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true
    
    $proc = [System.Diagnostics.Process]::Start($pinfo)
    $proc.WaitForExit()
    
    if (-not (Test-Path $keyFile)) {
        Write-Err "Konnte SSH-Key nicht generieren."
        throw "ssh-keygen fehlgeschlagen."
    }
    return $keyFile
}

function Build-CloudInitYaml {
    param([string]$GitHubUser, [string]$PubKey)

    $sshBlock = ""
    if ($GitHubUser) {
        $sshBlock = @"

  - name: pfadiadmin
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - gh:$GitHubUser
      - $PubKey
"@
    } else {
        $sshBlock = @"

  - name: pfadiadmin
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - $PubKey
"@
    }

    $yaml = @"
#cloud-config
ssh_pwauth: false
users:$sshBlock
package_update: true
package_upgrade: true
packages:
  - git
  - curl
  - openssl
  - fail2ban
  - unattended-upgrades
  - ufw
runcmd:
  # Root Login strikt auf SSH-Keys beschraenken (prohibit-password)
  - sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
  - sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
  - systemctl restart ssh
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow 22/tcp
  - ufw allow 80/tcp
  - ufw allow 443/tcp
  - ufw --force enable
  - echo 'APT::Periodic::Update-Package-Lists "1";' > /etc/apt/apt.conf.d/20auto-upgrades
  - echo 'APT::Periodic::Unattended-Upgrade "1";' >> /etc/apt/apt.conf.d/20auto-upgrades
  # Aktiviere die SSH-Bridge fuer den Installationsvorgang
  - mkdir -p /root/.ssh
  - echo "$PubKey" >> /root/.ssh/authorized_keys
  - chmod 600 /root/.ssh/authorized_keys
"@
    return $yaml
}

function Start-SSHBridge {
    param([string]$IP, [string]$Port, [bool]$UseKey, [string]$KeyFile)

    Write-Step 2 2 "SSH-Bridge starten"

    $sshCmd = "curl -sL $($Script:BOOTSTRAP_URL) -o /tmp/bootstrap.sh && bash /tmp/bootstrap.sh"
    
    if ($UseKey) {
        Write-Info "Warte bis der Server via SSH erreichbar ist (Port $Port)..."
        $maxRetries = 60
        $connected = $false
        for ($i = 1; $i -le $maxRetries; $i++) {
            $tnc = Test-NetConnection -ComputerName $IP -Port $Port -WarningAction SilentlyContinue
            if ($tnc.TcpTestSucceeded) {
                $connected = $true
                break
            }
            Start-Sleep -Seconds 3
        }

        if (-not $connected) {
            Write-Err "Server antwortet nicht. Setup abgebrochen."
            exit 1
        }

        Write-Info "Server online! Lade interaktives Menue..."
        Start-Sleep -Seconds 15

        Write-Color "--- Tunnel etabliert. ---" Green
        
        # -t erzwingt TTY, StrictHostKeyChecking=accept-new schuetzt vor Prompt
        & ssh.exe -t -o StrictHostKeyChecking=accept-new -i $KeyFile -p $Port "root@$IP" $sshCmd

        Remove-Item $KeyFile -Force -ErrorAction SilentlyContinue
        Remove-Item "$KeyFile.pub" -Force -ErrorAction SilentlyContinue
    } else {
        Write-Color "--- Tunnel etabliert. ---" Green
        Write-Warn "Du wirst gleich nach deinem Root-Passwort gefragt."
        & ssh.exe -t -o StrictHostKeyChecking=accept-new -p $Port "root@$IP" $sshCmd
    }

    Write-Host ""
    Write-Success "Bridge beendet. Der Server laeuft autark weiter!"
}

function Invoke-HetznerDeploy {
    param([hashtable]$HetznerConfig)
    
    $keyFile = New-EphemeralKey
    $pubKey = (Get-Content "$keyFile.pub" -Raw).Trim()

    $cloudInit = Build-CloudInitYaml -GitHubUser $HetznerConfig.GitHubUser -PubKey $pubKey

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
        Write-Err "Hetzner API Fehler: $_"
        throw "Server-Erstellung fehlgeschlagen."
    }

    $serverIP = $response.server.public_net.ipv4.ip
    $rootPassword = $response.root_password

    Write-Success "Server erstellt! (IP: $serverIP)"
    Write-Host ""
    Write-Color "Root-Passwort: $rootPassword" Yellow
    Write-Info "(SICHER AUFBEWAHREN, WIRD NUR EINMAL ANGEZEIGT!)"
    Write-Host
    Start-SSHBridge -IP $serverIP -Port 22 -UseKey $true -KeyFile $keyFile
}

function Invoke-SSHDeploy {
    param([hashtable]$SSHConfig)
    Start-SSHBridge -IP $SSHConfig.IP -Port $SSHConfig.Port -UseKey $false
}

function Invoke-LocalDeploy {
    Write-Step 2 2 "Lokale Einrichtung"
    Write-Err "Lokales Deployment ist auf Windows nicht machbar."
    Write-Host "Bitte nutze dieses Skript von einem nativen Linux-Rechner"
    Write-Host "oder nutze die Hetzner/SSH Option."
    exit 1
}

# ╔════════════════════════════════════════════════════════════════════╗
# ║                          HAUPTPROGRAMM                            ║
# ╚════════════════════════════════════════════════════════════════════╝

try {
    $provider = Get-ProviderChoice

    $config = @{}
    if ($provider -eq "1") { $config = Get-HetznerConfig }
    if ($provider -eq "2") { $config = Get-SSHConfig }

    Write-Host ""
    Write-Color "================================================" Cyan
    Write-Color " Server bereit zum Setup!" Green
    Write-Color "================================================" Cyan
    Write-Host ""

    if (-not (Read-YesNo "Mit der Einrichtung fortfahren?")) {
        exit 0
    }

    if ($provider -eq "1") { Invoke-HetznerDeploy -HetznerConfig $config }
    if ($provider -eq "2") { Invoke-SSHDeploy -SSHConfig $config }
    if ($provider -eq "3") { Invoke-LocalDeploy }
} catch {
    Write-Host ""
    Write-Err "Setup unterbrochen / Fehler aufgetreten: $_"
    # Cleanup Key if fails
    $sshDir = Join-Path $env:USERPROFILE ".ssh"
    $keyFile = Join-Path $sshDir "pfadi_setup_key_tmp"
    if (Test-Path $keyFile) { Remove-Item $keyFile -Force -ErrorAction SilentlyContinue }
    if (Test-Path "$keyFile.pub") { Remove-Item "$keyFile.pub" -Force -ErrorAction SilentlyContinue }
    exit 1
}
