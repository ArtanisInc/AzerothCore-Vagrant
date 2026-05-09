#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

echo "----------------------------------------"
echo "AzerothCore - Monitoring"
echo "----------------------------------------"

echo "SERVER STATUS:"
if pgrep -x "authserver" > /dev/null; then
  echo "  [OK] Authserver: ACTIVE"
else
  echo "  [FAIL] Authserver: INACTIVE"
fi

if pgrep -x "worldserver" > /dev/null; then
  echo "  [OK] Worldserver: ACTIVE"
else
  echo "  [FAIL] Worldserver: INACTIVE"
fi

echo ""
echo "RESOURCE USAGE:"
USED_MEM=$(free -h | grep Mem | awk '{print $3}')
TOTAL_MEM=$(free -h | grep Mem | awk '{print $2}')
echo "  Memory: $USED_MEM / $TOTAL_MEM"
echo "  CPU: $(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')%"

echo ""
echo "MYSQL:"
if systemctl is-active --quiet mysql; then
  echo "  [OK] Status: ACTIVE"
else
  echo "  [FAIL] Status: INACTIVE"
fi

echo "----------------------------------------"
