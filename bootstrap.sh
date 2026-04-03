#!/bin/bash
set -euo pipefail

echo "========================================="
echo "   Pfadfinder Cloud Bootstrapper"
echo "========================================="

# 1. Sicherstellen, dass das Skript root-Rechte hat
if [[ $EUID -ne 0 ]]; then
   echo "Bitte führe dieses Skript als root aus (mit sudo)."
   exit 1
fi

echo "[1/4] Installiere grundlegende System-Abhängigkeiten..."
# apt-get noninteractive um Warnungen zu unterdrücken
DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get install -yqq git curl openssl >/dev/null

REPO_URL="https://github.com/DPSG-Eschborn/infrastructure-configs.git"
CLONE_DIR="/opt/pfadfinder-cloud"

echo "[2/4] Bereite Repository unter $CLONE_DIR vor..."
if [ -d "$CLONE_DIR/.git" ]; then
    echo "      Verzeichnis existiert bereits. Setze auf sauberen Haupt-Branch zurück..."
    cd "$CLONE_DIR"
    git fetch origin
    git checkout main
    git reset --hard origin/main
    git clean -fd
else
    echo "      Klone Repository..."
    git clone "$REPO_URL" "$CLONE_DIR"
    cd "$CLONE_DIR"
fi

echo "[3/4] Setze Berechtigungen..."
chmod +x setup.sh

echo "[4/4] Starte interaktives Setup-Menü..."
echo "-----------------------------------------"
./setup.sh --interactive
