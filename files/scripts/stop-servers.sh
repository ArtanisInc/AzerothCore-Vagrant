#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh
echo "Stopping systemd services..."
sudo systemctl stop acore-world
sudo systemctl stop acore-auth
echo "Servers stopped."
