#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

echo "Cleaning log files..."
if command -v logrotate >/dev/null 2>&1 && [ -f /etc/logrotate.d/acore ]; then
    sudo logrotate -f /etc/logrotate.d/acore
else
    rm -f "$AC_LOG_DIR"/*.log
    rm -f "$AC_LOG_DIR"/*.txt
fi
echo "[OK] Logs cleaned."
