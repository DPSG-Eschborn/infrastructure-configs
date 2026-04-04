@echo off
title Pfadfinder-Cloud Setup-Assistent
echo.
echo   ============================================
echo      Pfadfinder-Cloud Setup-Assistent
echo   ============================================
echo.
echo   Lade aktuelle Version herunter...
echo.

:: Lade deploy.ps1 direkt von GitHub in den TEMP-Ordner
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
    "try { " ^
    "  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
    "  $url = 'https://raw.githubusercontent.com/DPSG-Eschborn/infrastructure-configs/main/deploy.ps1'; " ^
    "  $dest = Join-Path $env:TEMP 'pfadfinder-deploy.ps1'; " ^
    "  Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing; " ^
    "  Write-Host '  [OK] Download erfolgreich.' -ForegroundColor Green; " ^
    "  Write-Host ''; " ^
    "  & $dest " ^
    "} catch { " ^
    "  Write-Host '[X] Download fehlgeschlagen. Pruefe deine Internetverbindung.' -ForegroundColor Red; " ^
    "  Write-Host $_.Exception.Message; " ^
    "  Read-Host 'Druecke Enter zum Beenden' " ^
    "}"

echo.
pause
