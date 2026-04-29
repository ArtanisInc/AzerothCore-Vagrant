#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

AUTH_PORT=3724
WORLD_PORT=8085
AUTH_LOG="/home/vagrant/azerothcore/env/dist/bin/Auth.log"
WORLD_LOG="/home/vagrant/azerothcore/env/dist/bin/Server.log"

FAILED=0

check_mysql() {
  if MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 -Nse "SELECT 1" >/dev/null 2>&1; then
    echo "[OK] mysql query"
  else
    echo "[FAIL] mysql query"
    FAILED=1
  fi
}

check_port() {
  local label="$1"
  local port="$2"
  if ss -ltn 2>/dev/null | grep -qE "[:.]${port}[[:space:]]"; then
    echo "[OK] port ${label} (${port})"
  else
    echo "[FAIL] port ${label} (${port})"
    FAILED=1
  fi
}

process_running() {
  local proc="$1"
  pgrep -x "$proc" >/dev/null 2>&1
}

is_port_open() {
  local port="$1"
  ss -ltn 2>/dev/null | grep -qE "[:.]${port}[[:space:]]"
}

log_recently_updated() {
  local file="$1"
  local minutes="$2"

  if [ ! -f "$file" ]; then
    return 1
  fi

  find "$file" -mmin "-${minutes}" -print -quit | grep -q .
}

world_ready_seen() {
  if [ ! -f "$WORLD_LOG" ]; then
    return 1
  fi

  grep -Eq "worldserver-daemon\) ready|Worldserver listening connections on port ${WORLD_PORT}" "$WORLD_LOG"
}

check_worldserver_state() {
  local has_process=0
  local port_open=0
  local log_recent=0
  local ready_seen=0

  if process_running "worldserver"; then
    has_process=1
  fi
  if is_port_open "$WORLD_PORT"; then
    port_open=1
  fi
  if log_recently_updated "$WORLD_LOG" 3; then
    log_recent=1
  fi
  if world_ready_seen; then
    ready_seen=1
  fi

  if [ "$has_process" -eq 1 ]; then
    echo "[OK] process worldserver"
  else
    echo "[FAIL] process worldserver"
  fi

  if [ "$port_open" -eq 1 ]; then
    echo "[OK] port worldserver (${WORLD_PORT})"
    return 0
  fi

  if [ "$ready_seen" -eq 1 ]; then
    echo "[FAIL] worldserver post-ready indisponible (port ${WORLD_PORT} ferme apres ready)"
    FAILED=1
    return 0
  fi

  if [ "$has_process" -eq 1 ] && [ "$log_recent" -eq 1 ]; then
    echo "[WARN] worldserver STARTING (port ${WORLD_PORT} ferme, log recent <=3m)"
    return 0
  fi

  echo "[FAIL] worldserver indisponible (port ${WORLD_PORT} ferme, pas de progression log <=3m ou process absent)"
  FAILED=1
}

check_recent_log_marker() {
  local file="$1"
  local label="$2"
  if [ ! -f "$file" ]; then
    echo "[WARN] log ${label} absent (${file})"
    return 0
  fi

  if find "$file" -mmin -15 -print -quit | grep -q .; then
    echo "[OK] log ${label} recent"
  else
    echo "[WARN] log ${label} non recent (>15m)"
  fi
}

echo "=== AzerothCore healthcheck ==="
check_mysql
if process_running "authserver"; then
  echo "[OK] process authserver"
else
  echo "[FAIL] process authserver"
  FAILED=1
fi
check_port "authserver" "$AUTH_PORT"
check_worldserver_state
check_recent_log_marker "$AUTH_LOG" "Auth.log"
check_recent_log_marker "$WORLD_LOG" "Server.log"

if [ "$FAILED" -ne 0 ]; then
  echo "Healthcheck: FAIL"
  exit 1
fi

echo "Healthcheck: OK"
