#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh
echo "Demarrage des services Systemd..."
sudo systemctl start acore-auth
sudo systemctl start acore-world

echo "Services demarres !"
echo "Attendez quelques instants que le worldserver s'initialise."
echo "Pour voir les logs: acore-log"
echo "Pour suivre le journal worldserver: acore-console"
