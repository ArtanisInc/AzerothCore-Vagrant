#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

echo "========================================"
echo "Installing system prerequisites"
echo "========================================"

echo "Removing problematic MySQL sources..."
rm -f /etc/apt/sources.list.d/mysql.list

# System update (after source cleanup)
apt-get update -qq

echo "Disabling system auto-upgrades..."
sed -i 's/1/0/g' /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null || true

echo "----------------------------------------"
echo "SWAP configuration (anti-crash)"
echo "----------------------------------------"

if [ ! -f /swapfile ]; then
    echo "Creating a 2 GB swap file..."
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
    echo "[OK] Swap enabled successfully."
else
    echo "[OK] Swap already present."
fi

# Dependency installation
apt-get install -y git cmake make g++ clang libssl-dev libbz2-dev libreadline-dev libncurses-dev libboost-all-dev unzip wget
echo "[OK] Dependencies installed."
