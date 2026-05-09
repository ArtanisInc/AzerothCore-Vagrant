#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh
echo "Starting systemd services..."
sudo systemctl start acore-auth
sudo systemctl start acore-world

echo "Services started!"
echo "Wait a few moments for worldserver to initialize."
echo "To view logs: acore-log"
echo "To follow the worldserver journal: acore-console"
