#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

AUTH_PORT=3724
WORLD_PORT=8085
MYSQL_PORT=3306
AUTH_LOG="${AC_BIN_DIR}/Auth.log"
WORLD_LOG="${AC_BIN_DIR}/Server.log"
MYSQL_HOST="${DB_HOST:-127.0.0.1}"
SOAP_PORT="${SOAP_PORT:-7878}"
SOAP_USER="${SOAP_USER:-admin}"
SOAP_PASS="${SOAP_PASS:-admin}"

section() {
  printf '\n==== %s ====\n' "$1"
}

run_optional() {
  local label="$1"
  shift

  echo "-- $label"
  "$@" 2>&1 || echo "[WARN] Command unavailable or failed: $*"
}

mysql_query() {
  MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h "$MYSQL_HOST" --protocol=tcp "$@"
}

mysql_query_silent() {
  MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h "$MYSQL_HOST" --protocol=tcp -Nse "$@"
}

port_state() {
  local label="$1"
  local port="$2"

  if ss -ltn 2>/dev/null | grep -qE "[:.]${port}[[:space:]]"; then
    echo "[OK] ${label} port ${port} open"
  else
    echo "[FAIL] ${label} port ${port} closed"
  fi
}

service_report() {
  local svc="$1"

  printf '%-14s active=%s enabled=%s\n' \
    "$svc" \
    "$(systemctl is-active "$svc" 2>/dev/null || echo unknown)" \
    "$(systemctl is-enabled "$svc" 2>/dev/null || echo unknown)"
}

failed_units_report() {
  local output

  output="$(systemctl --failed --no-pager --plain 2>&1 || true)"
  echo "-- systemctl failed units"

  if printf '%s
' "$output" | grep -qE '^[^[:space:]]+\.service[[:space:]]'; then
    printf '%s
' "$output"
  elif printf '%s
' "$output" | grep -q '0 loaded units listed'; then
    echo "[OK] no failed systemd units"
  else
    printf '%s
' "$output"
  fi
}

process_report() {
  local proc="$1"

  if pgrep -x "$proc" >/dev/null 2>&1; then
    echo "[OK] process $proc"
    ps -C "$proc" -o pid,etime,%cpu,%mem,cmd --no-headers 2>/dev/null || true
  else
    echo "[FAIL] process $proc missing"
  fi
}

log_errors() {
  local label="$1"
  local file="$2"

  echo "-- $label ($file)"
  if [ ! -f "$file" ]; then
    echo "[WARN] Log missing"
    return 0
  fi

  echo "taille=$(stat -c '%s' "$file" 2>/dev/null || echo 0) bytes, modifie=$(stat -c '%y' "$file" 2>/dev/null || echo unknown)"
  grep -Ein 'error|fail|fatal|exception|crash' "$file" 2>/dev/null | tail -n 30 || echo "[OK] No recent error marker detected"
}

soap_report() {
  local payload
  local response

  if ! command -v curl >/dev/null 2>&1; then
    echo "[WARN] curl missing, SOAP check impossible"
    return 0
  fi

  payload="<?xml version=\"1.0\" encoding=\"utf-8\"?><SOAP-ENV:Envelope xmlns:SOAP-ENV=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:ns1=\"urn:AC\"><SOAP-ENV:Body><ns1:executeCommand><command>server info</command></ns1:executeCommand></SOAP-ENV:Body></SOAP-ENV:Envelope>"

  if response="$(curl -fsS --max-time 8 -u "${SOAP_USER}:${SOAP_PASS}" \
      -H 'Content-Type: text/xml; charset=utf-8' \
      -H 'SOAPAction: "urn:AC#executeCommand"' \
      --data "$payload" \
      "http://127.0.0.1:${SOAP_PORT}/" 2>/dev/null)"; then
    echo "[OK] SOAP available sur 127.0.0.1:${SOAP_PORT}"
    printf '%s\n' "$response" | sed -E 's/<[^>]+>/ /g; s/[[:space:]]+/ /g' | cut -c1-500
    echo
  else
    echo "[WARN] SOAP unavailable or invalid credentials sur 127.0.0.1:${SOAP_PORT}"
  fi
}

core_version_report() {
  if [ -d "$AC_CODE_DIR/.git" ]; then
    echo "core path: $AC_CODE_DIR"
    git -C "$AC_CODE_DIR" log -1 --pretty='commit=%h date=%ci subject=%s' 2>/dev/null || true
    git -C "$AC_CODE_DIR" status --short 2>/dev/null | sed 's/^/  /' || true
  else
    echo "[WARN] Repository core missing: $AC_CODE_DIR"
  fi

  if [ -d "$AC_CODE_DIR/modules" ]; then
    echo "-- modules git"
    for module_dir in "$AC_CODE_DIR"/modules/*; do
      [ -d "$module_dir/.git" ] || continue
      printf '%-36s ' "$(basename "$module_dir")"
      git -C "$module_dir" log -1 --pretty='%h %ci %s' 2>/dev/null || echo "unknown revision"
    done
  fi
}

module_detection_report() {
  echo "-- module configuration files"
  if [ -d "$AC_CONF_DIR/modules" ]; then
    find "$AC_CONF_DIR/modules" -maxdepth 1 -type f -name '*.conf' -printf '%f\n' 2>/dev/null | sort || true
  else
    echo "[WARN] Module config directory missing: $AC_CONF_DIR/modules"
  fi

  echo "-- module markers in Server.log"
  if [ -f "$WORLD_LOG" ]; then
    grep -Ei 'module|playerbot|ahbot|autobalance|transmog|reagent|daily|portal|rare|aoe|solo|challenge|fly' "$WORLD_LOG" 2>/dev/null | tail -n 80 || echo "[WARN] No module marker found in Server.log"
  else
    echo "[WARN] Server.log missing"
  fi
}

database_report() {
  if ! mysql_query_silent "SELECT 1" >/dev/null 2>&1; then
    echo "[FAIL] MySQL connection failed with DB_USER=$DB_USER host=$MYSQL_HOST"
    return 0
  fi

  echo "[OK] MySQL connection"

  echo "-- realmlist"
  mysql_query -e "SELECT id,name,address,localAddress,port FROM acore_auth.realmlist;" 2>&1 || true

  echo "-- database sizes (MiB)"
  mysql_query -e "
    SELECT table_schema AS db,
           ROUND(SUM(data_length + index_length) / 1024 / 1024, 1) AS size_mib
    FROM information_schema.tables
    WHERE table_schema IN ('acore_auth','acore_characters','acore_world','acore_playerbots')
    GROUP BY table_schema
    ORDER BY table_schema;" 2>&1 || true

  echo "-- tables per database"
  mysql_query -e "
    SELECT table_schema AS db, COUNT(*) AS tables
    FROM information_schema.tables
    WHERE table_schema IN ('acore_auth','acore_characters','acore_world','acore_playerbots')
    GROUP BY table_schema
    ORDER BY table_schema;" 2>&1 || true
}

echo "AzerothCore diagnostic - $(date -Iseconds)"
echo "host=$(hostname) user=$(id -un) ac_code=$AC_CODE_DIR ac_install=$AC_INSTALL_DIR"

section "Existing healthcheck summary"
if [ -x /home/vagrant/healthcheck.sh ]; then
  /home/vagrant/healthcheck.sh || true
else
  echo "[WARN] /home/vagrant/healthcheck.sh missing"
fi

section "Existing metrics snapshot"
if [ -x /home/vagrant/metrics-snapshot.sh ]; then
  /home/vagrant/metrics-snapshot.sh || true
else
  echo "[WARN] /home/vagrant/metrics-snapshot.sh missing"
fi

section "Systemd"
service_report mysql
service_report acore-auth
service_report acore-world
failed_units_report

section "Processus"
process_report mysqld
process_report authserver
process_report worldserver

section "Ports"
port_state mysql "$MYSQL_PORT"
port_state authserver "$AUTH_PORT"
port_state worldserver "$WORLD_PORT"
ss -ltnp 2>/dev/null | grep -E ":(${MYSQL_PORT}|${AUTH_PORT}|${WORLD_PORT}|${SOAP_PORT})[[:space:]]" || true

section "Resources"
run_optional "uptime" uptime
run_optional "memory" free -h
run_optional "disk" df -h / /home /vagrant
run_optional "top CPU" sh -c "ps -eo pid,comm,%cpu,%mem,etime --sort=-%cpu | head -n 12"

section "MySQL et bases"
database_report

section "SOAP"
soap_report

section "Versions core/modules"
core_version_report

section "Modules detectables"
module_detection_report

section "Latest application log errors"
log_errors "Auth.log" "$AUTH_LOG"
log_errors "Server.log" "$WORLD_LOG"

section "Recent systemd journals"
run_optional "acore-auth journal" journalctl -u acore-auth -n 80 --no-pager
run_optional "acore-world journal" journalctl -u acore-world -n 120 --no-pager
run_optional "mysql journal" journalctl -u mysql -n 80 --no-pager

echo
echo "[OK] Diagnostic complete"
