#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

restart_service=0
suggested_command="$*"

cleanup() {
    if [ "$restart_service" -eq 1 ]; then
        echo ""
        echo "Redemarrage du service acore-world..."
        sudo systemctl start acore-world >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

cd "$AC_BIN_DIR"

echo "Passage en mode console maintenance."
echo "Le service acore-world va etre arrete temporairement."
if [ -n "$suggested_command" ]; then
    echo "Commande suggeree a executer une fois la console ouverte :"
    echo "  $suggested_command"
fi
echo "Quittez la console worldserver pour relancer le service automatiquement."
sudo systemctl stop acore-world >/dev/null 2>&1 || true
restart_service=1
exec ./worldserver
