#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh
echo "Arret des services Systemd..."
sudo systemctl stop acore-world
sudo systemctl stop acore-auth
echo "Serveurs arretes."
