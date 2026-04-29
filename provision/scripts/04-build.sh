#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

echo "========================================"
echo "Compilation d'AzerothCore"
echo "========================================"

mkdir -p "$AC_CODE_DIR/build"
cd "$AC_CODE_DIR/build"

CPU_COUNT="${VM_CPUS:-1}"
if ! [[ "$CPU_COUNT" =~ ^[0-9]+$ ]] || [ "$CPU_COUNT" -lt 1 ]; then
    CPU_COUNT=1
fi

# Configuration CMake
echo "--- Configuration CMake ---"
cmake ../ -DCMAKE_INSTALL_PREFIX="$AC_INSTALL_DIR" \
      -DCMAKE_C_COMPILER=/usr/bin/clang \
      -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
      -DWITH_WARNINGS=1 \
      -DTOOLS_BUILD=all \
      -DSCRIPTS=static \
      -DMODULES=static \
      -DMODULE_MOD_PLAYERBOTS=static \
      -DCMAKE_C_FLAGS="-O3 -march=native" \
      -DCMAKE_CXX_FLAGS="-O3 -march=native"

# Compilation
echo "--- Compilation (Cores: $CPU_COUNT) ---"
make -j"$CPU_COUNT"

# Installation
echo "--- Installation ---"
make install

echo "[OK] Compilation et installation terminees."

if [ -f "$AC_BIN_DIR/worldserver" ] && [ -f "$AC_BIN_DIR/authserver" ]; then
    echo "[OK] Binaires authserver et worldserver prets."
else
    echo "[ERROR] Echec de la compilation."
    exit 1
fi
