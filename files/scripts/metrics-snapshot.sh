#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

service_state() {
  local svc="$1"
  if systemctl is-active --quiet "$svc"; then
    printf '"active"'
  else
    local state
    state="$(systemctl is-active "$svc" 2>/dev/null || true)"
    [ -z "$state" ] && state="unknown"
    printf '"%s"' "$state"
  fi
}

process_present() {
  local name="$1"
  if pgrep -x "$name" >/dev/null 2>&1; then
    printf 'true'
  else
    printf 'false'
  fi
}

port_open() {
  local port="$1"
  if ss -ltn 2>/dev/null | grep -qE "[:.]${port}[[:space:]]"; then
    printf 'true'
  else
    printf 'false'
  fi
}

log_size() {
  local file="$1"
  if [ -f "$file" ]; then
    stat -c '%s' "$file"
  else
    printf '0'
  fi
}

AUTH_LOG="${AC_LOG_DIR}/Auth.log"
WORLD_LOG="${AC_LOG_DIR}/Server.log"

cat <<JSON
{
  "timestamp": "$(date -Iseconds)",
  "uptime_seconds": "$(cut -d. -f1 /proc/uptime)",
  "systemd": {
    "acore-auth": $(service_state acore-auth),
    "acore-world": $(service_state acore-world),
    "mysql": $(service_state mysql)
  },
  "process": {
    "authserver": $(process_present authserver),
    "worldserver": $(process_present worldserver)
  },
  "ports": {
    "3724": $(port_open 3724),
    "8085": $(port_open 8085)
  },
  "logs": {
    "Auth.log_size": $(log_size "$AUTH_LOG"),
    "Server.log_size": $(log_size "$WORLD_LOG")
  }
}
JSON
