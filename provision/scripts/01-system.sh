#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

echo "========================================"
echo "Installation des prerequis systeme"
echo "========================================"

echo "Suppression des sources MySQL problematiques..."
rm -f /etc/apt/sources.list.d/mysql.list

# Mise a jour du systeme (apres nettoyage des sources)
apt-get update -qq

echo "Desactivation des auto-upgrades du systeme..."
sed -i 's/1/0/g' /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null || true

echo "----------------------------------------"
echo "Configuration du SWAP (Anti-Crash)"
echo "----------------------------------------"

if [ ! -f /swapfile ]; then
    echo "Creation d'un fichier swap de 2Go..."
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
    echo "[OK] Swap active avec succes."
else
    echo "[OK] Swap deja present."
fi

# Installation des dependances
apt-get install -y git cmake make g++ clang libssl-dev libbz2-dev libreadline-dev libncurses-dev libboost-all-dev unzip wget
echo "[OK] Dependances installees."
