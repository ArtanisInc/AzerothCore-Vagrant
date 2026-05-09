#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

echo "========================================"
echo "Import SQL AzerothCore (dbimport)"
echo "========================================"

ACORE_BIN_DIR="${ACORE_BIN_DIR:-$AC_CODE_DIR/env/dist/bin}"

if [ ! -d "$ACORE_BIN_DIR" ]; then
  echo "[ERROR] bin directory not found: $ACORE_BIN_DIR"
  exit 1
fi

DBIMPORT="$ACORE_BIN_DIR/dbimport"

if [ ! -f "$DBIMPORT" ]; then
  echo "[ERROR] dbimport not found in $ACORE_BIN_DIR"
  exit 1
fi

if [ ! -x "$DBIMPORT" ]; then
  echo "[ERROR] dbimport exists but is not executable: $DBIMPORT"
  exit 1
fi

cd "$ACORE_BIN_DIR"

echo "[OK] dbimport detected, running in idempotent mode..."
if "$DBIMPORT" all; then
  echo "[OK] SQL import (core + modules) complete."
elif "$DBIMPORT"; then
  echo "[OK] SQL import (core + modules) complete."
else
  echo "[ERROR] dbimport failed"
  exit 1
fi
