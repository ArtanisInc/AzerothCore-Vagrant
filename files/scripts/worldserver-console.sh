#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

restart_service=0
suggested_command="$*"

cleanup() {
    if [ "$restart_service" -eq 1 ]; then
        echo ""
        echo "Restarting acore-world service..."
        sudo systemctl start acore-world >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

cd "$AC_BIN_DIR"

echo "Switching to maintenance console mode."
echo "The acore-world service will be stopped temporarily."
if [ -n "$suggested_command" ]; then
    echo "Suggested command to run once the console is open:"
    echo "  $suggested_command"
fi
echo "Exit the worldserver console to restart the service automatically."
sudo systemctl stop acore-world >/dev/null 2>&1 || true
restart_service=1
exec ./worldserver
