#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

echo "========================================"
echo "Import SQL AzerothCore (dbimport)"
echo "========================================"

ACORE_BIN_DIR="${ACORE_BIN_DIR:-$AC_CODE_DIR/env/dist/bin}"

if [ ! -d "$ACORE_BIN_DIR" ]; then
  echo "[ERROR] Dossier bin introuvable: $ACORE_BIN_DIR"
  exit 1
fi

DBIMPORT="$ACORE_BIN_DIR/dbimport"

if [ ! -f "$DBIMPORT" ]; then
  echo "[ERROR] dbimport introuvable dans $ACORE_BIN_DIR"
  exit 1
fi

if [ ! -x "$DBIMPORT" ]; then
  echo "[ERROR] dbimport present mais non executable: $DBIMPORT"
  exit 1
fi

cd "$ACORE_BIN_DIR"

echo "[OK] dbimport detecte, execution en mode idempotent..."
if "$DBIMPORT" all; then
  echo "[OK] Import SQL (core + modules) termine."
elif "$DBIMPORT"; then
  echo "[OK] Import SQL (core + modules) termine."
else
  echo "[ERROR] Echec de dbimport"
  exit 1
fi
