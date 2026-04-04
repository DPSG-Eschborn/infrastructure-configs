@echo off
title Pfadfinder-Cloud Setup-Assistent
echo.
echo   Starte Pfadfinder-Cloud Setup-Assistenten...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1"
echo.
pause
