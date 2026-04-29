#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

echo "----------------------------------------"
echo "AzerothCore - Monitoring"
echo "----------------------------------------"

echo "STATUT DES SERVEURS:"
if pgrep -x "authserver" > /dev/null; then
  echo "  [OK] Authserver: ACTIF"
else
  echo "  [FAIL] Authserver: INACTIF"
fi

if pgrep -x "worldserver" > /dev/null; then
  echo "  [OK] Worldserver: ACTIF"
else
  echo "  [FAIL] Worldserver: INACTIF"
fi

echo ""
echo "UTILISATION RESSOURCES:"
USED_MEM=$(free -h | grep Mem | awk '{print $3}')
TOTAL_MEM=$(free -h | grep Mem | awk '{print $2}')
echo "  Memoire: $USED_MEM / $TOTAL_MEM"
echo "  CPU: $(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')%"

echo ""
echo "MYSQL:"
if systemctl is-active --quiet mysql; then
  echo "  [OK] Statut: ACTIF"
else
  echo "  [FAIL] Statut: INACTIF"
fi

echo "----------------------------------------"
