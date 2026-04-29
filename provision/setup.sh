#!/bin/bash

set -Eeuo pipefail

echo "========================================"
echo "AzerothCore Provisioning Master Orchestrator"
echo "========================================"

SCRIPTS_DIR="/vagrant/provision/scripts"

# Call scripts in order
echo "--- Running 01-system.sh ---"
bash "$SCRIPTS_DIR/01-system.sh"

echo "--- Running 02-mysql.sh ---"
bash "$SCRIPTS_DIR/02-mysql.sh"

echo "--- Running 025-sysctl.sh ---"
bash "$SCRIPTS_DIR/025-sysctl.sh"

echo "--- Running 03-source.sh ---"
bash "$SCRIPTS_DIR/03-source.sh"

echo "--- Running 04-build.sh ---"
bash "$SCRIPTS_DIR/04-build.sh"

echo "--- Running 05-config.sh ---"
bash "$SCRIPTS_DIR/05-config.sh"

echo "--- Running 054-world-id-precheck.sh ---"
bash "$SCRIPTS_DIR/054-world-id-precheck.sh"

echo "--- Running 055-db-import.sh ---"
bash "$SCRIPTS_DIR/055-db-import.sh"

echo "--- Running 06-services.sh ---"
bash "$SCRIPTS_DIR/06-services.sh"

echo "========================================"
echo "Provisioning complete!"
echo "========================================"
