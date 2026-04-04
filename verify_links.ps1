#!/usr/bin/env pwsh
# Temporaeres Test-Skript: Verifiziert, dass die GitHub-URLs den richtigen Code liefern.
# Nach dem Test loeschen: Remove-Item .\verify_links.ps1

$ErrorActionPreference = "Continue"
$pass = 0
$fail = 0

Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host "   Pfadfinder-Cloud Link-Verifikation" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# --- Test 1: bootstrap.sh RAW URL erreichbar ---
Write-Host "`n[Test 1] bootstrap.sh RAW-URL erreichbar?" -ForegroundColor Yellow
$rawUrl = "https://raw.githubusercontent.com/DPSG-Eschborn/infrastructure-configs/main/bootstrap.sh"
try {
    $response = Invoke-WebRequest -Uri $rawUrl -UseBasicParsing -TimeoutSec 10
    if ($response.StatusCode -eq 200) {
        Write-Host "  PASS: HTTP 200 OK" -ForegroundColor Green
        $pass++
    } else {
        Write-Host "  FAIL: HTTP $($response.StatusCode)" -ForegroundColor Red
        $fail++
    }
} catch {
    Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $fail++
}

# --- Test 2: Inhalt ist ein gueltiges Bash-Skript (beginnt mit Shebang) ---
Write-Host "`n[Test 2] bootstrap.sh beginnt mit #!/bin/bash?" -ForegroundColor Yellow
$remoteContent = $response.Content
if ($remoteContent -match "^#!/bin/bash") {
    Write-Host "  PASS: Shebang gefunden" -ForegroundColor Green
    $pass++
} else {
    Write-Host "  FAIL: Kein Shebang - moeglicherweise HTML-Fehlerseite?" -ForegroundColor Red
    $fail++
}

# --- Test 3: Inhalt stimmt mit lokalem bootstrap.sh ueberein ---
Write-Host "`n[Test 3] Remote bootstrap.sh == lokale bootstrap.sh?" -ForegroundColor Yellow
$localContent = Get-Content -Path ".\bootstrap.sh" -Raw
# Normalisiere Zeilenenden fuer Vergleich
$remoteNorm = $remoteContent -replace "`r`n", "`n"
$localNorm = $localContent -replace "`r`n", "`n"
if ($remoteNorm.Trim() -eq $localNorm.Trim()) {
    Write-Host "  PASS: Identisch" -ForegroundColor Green
    $pass++
} else {
    Write-Host "  WARN: Nicht identisch! (Lokale Aenderungen noch nicht gepusht?)" -ForegroundColor DarkYellow
    # Zeige Unterschiede
    $remoteLines = $remoteNorm.Trim() -split "`n"
    $localLines = $localNorm.Trim() -split "`n"
    Write-Host "    Remote: $($remoteLines.Count) Zeilen, Lokal: $($localLines.Count) Zeilen" -ForegroundColor DarkYellow
    $fail++
}

# --- Test 4: Git-Repo ist klonbar (HTTPS check) ---
Write-Host "`n[Test 4] Git-Repository erreichbar (HTTPS)?" -ForegroundColor Yellow
$repoUrl = "https://github.com/DPSG-Eschborn/infrastructure-configs.git"
try {
    $gitCheck = Invoke-WebRequest -Uri "https://github.com/DPSG-Eschborn/infrastructure-configs" -UseBasicParsing -TimeoutSec 10
    if ($gitCheck.StatusCode -eq 200) {
        Write-Host "  PASS: Repository existiert und ist oeffentlich" -ForegroundColor Green
        $pass++
    } else {
        Write-Host "  FAIL: HTTP $($gitCheck.StatusCode)" -ForegroundColor Red
        $fail++
    }
} catch {
    Write-Host "  FAIL: Repository nicht erreichbar - $($_.Exception.Message)" -ForegroundColor Red
    $fail++
}

# --- Test 5: setup.sh existiert im Remote-Repo ---
Write-Host "`n[Test 5] setup.sh im Remote-Repo vorhanden?" -ForegroundColor Yellow
$setupUrl = "https://raw.githubusercontent.com/DPSG-Eschborn/infrastructure-configs/main/setup.sh"
try {
    $setupResp = Invoke-WebRequest -Uri $setupUrl -UseBasicParsing -TimeoutSec 10
    if ($setupResp.StatusCode -eq 200 -and $setupResp.Content -match "^#!/bin/bash") {
        Write-Host "  PASS: setup.sh gefunden und gueltig" -ForegroundColor Green
        $pass++
    } else {
        Write-Host "  FAIL: setup.sh nicht valide" -ForegroundColor Red
        $fail++
    }
} catch {
    Write-Host "  FAIL: setup.sh nicht erreichbar" -ForegroundColor Red
    $fail++
}

# --- Test 6: Remote setup.sh stimmt mit lokalem ueberein ---
Write-Host "`n[Test 6] Remote setup.sh == lokale setup.sh?" -ForegroundColor Yellow
$remoteSetup = ($setupResp.Content) -replace "`r`n", "`n"
$localSetup = (Get-Content -Path ".\setup.sh" -Raw) -replace "`r`n", "`n"
if ($remoteSetup.Trim() -eq $localSetup.Trim()) {
    Write-Host "  PASS: Identisch" -ForegroundColor Green
    $pass++
} else {
    Write-Host "  WARN: Nicht identisch! (Deine Bugfixes sind lokal, aber noch nicht gepusht)" -ForegroundColor DarkYellow
    $remoteSetupLines = $remoteSetup.Trim() -split "`n"
    $localSetupLines = $localSetup.Trim() -split "`n"
    Write-Host "    Remote: $($remoteSetupLines.Count) Zeilen, Lokal: $($localSetupLines.Count) Zeilen" -ForegroundColor DarkYellow
    $fail++
}

# --- Test 7: hetzner-basic-node.yaml referenziert die korrekte Repo-URL ---
Write-Host "`n[Test 7] hetzner-basic-node.yaml zeigt auf das richtige Repo?" -ForegroundColor Yellow
$hetznerContent = Get-Content -Path ".\cloud-configs\hetzner-basic-node.yaml" -Raw
if ($hetznerContent -match "github.com/DPSG-Eschborn/infrastructure-configs") {
    Write-Host "  PASS: Korrekte Repo-URL in Hetzner YAML" -ForegroundColor Green
    $pass++
} else {
    Write-Host "  FAIL: Falsche oder fehlende Repo-URL" -ForegroundColor Red
    $fail++
}

# --- Ergebnis ---
Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host "   Ergebnis: $pass PASS / $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Yellow" })
Write-Host "=========================================" -ForegroundColor Cyan

if ($fail -gt 0) {
    Write-Host "`nHinweis: Falls Tests 3 oder 6 fehlschlagen, liegt das wahrscheinlich" -ForegroundColor DarkYellow
    Write-Host "daran, dass die lokalen Bugfixes noch nicht nach GitHub gepusht wurden." -ForegroundColor DarkYellow
    Write-Host "Nach 'git push' sollten alle Tests PASS sein.`n" -ForegroundColor DarkYellow
}
