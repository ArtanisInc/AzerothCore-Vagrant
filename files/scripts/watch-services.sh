#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

INTERVAL="${1:-30}"
OUT_FILE="${AC_LOG_DIR}/health.log"

if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [ "$INTERVAL" -lt 5 ]; then
  echo "Usage: $0 [interval_seconds>=5]" >&2
  exit 2
fi

mkdir -p "$AC_LOG_DIR"

echo "[INFO] watch-services start interval=${INTERVAL}s log=${OUT_FILE}"
while true; do
  {
    printf '[%s] ' "$(date -Iseconds)"
    /home/vagrant/healthcheck.sh
  } >> "$OUT_FILE" 2>&1 || true
  sleep "$INTERVAL"
done
