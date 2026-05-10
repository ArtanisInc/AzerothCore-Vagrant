#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

AHBOT_ACCOUNT_NAME="${AHBOT_ACCOUNT_NAME:-ahbot}"
AHBOT_ACCOUNT_PASS="${AHBOT_ACCOUNT_PASS:-ahbot123!}"

echo "========================================"
echo "Configuring Systemd"
echo "========================================"

cp /vagrant/files/systemd/acore-auth.service /etc/systemd/system/
cp /vagrant/files/systemd/acore-world.service /etc/systemd/system/
cp /vagrant/files/logrotate/acore /etc/logrotate.d/acore

systemctl daemon-reload
systemctl enable acore-auth
systemctl enable acore-world
echo "[OK] Systemd services installed."

echo "========================================"
echo "Installing scripts"
echo "========================================"

mkdir -p "$AC_LOG_DIR"
chown vagrant:vagrant "$AC_LOG_DIR"

cp /vagrant/files/scripts/*.sh /home/vagrant/
cp /vagrant/files/scripts/*.py /home/vagrant/ 2>/dev/null || true
chmod +x /home/vagrant/*.sh /home/vagrant/*.py 2>/dev/null || true
chown vagrant:vagrant /home/vagrant/*

echo "[OK] Management scripts installed."

cat > /home/vagrant/.bash_aliases <<ALIASES
alias acore-start='./start-servers.sh'
alias acore-stop='./stop-servers.sh'
alias acore-restart='./stop-servers.sh && ./start-servers.sh'
alias acore-status='./monitor-servers.sh'
alias acore-log='tail -f /home/vagrant/azerothcore/env/dist/bin/Server.log'
alias acore-console='journalctl -u acore-world -f'
alias acore-auth='journalctl -u acore-auth -f'
alias acore-db='MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 acore_world'
alias acore-conf='nano /home/vagrant/azerothcore/env/dist/etc/worldserver.conf'
alias acore-modules='cd /home/vagrant/azerothcore/env/dist/etc/modules && ls -l'
alias acore-errors='grep "ERROR" /home/vagrant/azerothcore/env/dist/bin/Server.log | tail -n 20'
alias acore-world-console='./worldserver-console.sh'
alias acore-create-account='./create-account.sh'
alias acore-set-gm='./set-gm.sh'
alias acore-bots-help='./playerbots-help.sh'
alias acore-setup-ahbot='./setup-ahbot.sh'
alias acore-clean-logs='./clean-logs.sh'
alias acore-backup='./backup-db.sh'
alias acore-update='./update-core.sh'
alias acore-health='./healthcheck.sh'
alias acore-metrics='./metrics-snapshot.sh'
alias acore-diagnose='./diagnose-server.sh'
alias acore-watch='./watch-services.sh'
ALIASES
chown vagrant:vagrant /home/vagrant/.bash_aliases

# Optional periodic healthcheck via cron (non-blocking)
cat > /etc/cron.d/acore-health <<'CRON'
*/5 * * * * vagrant /home/vagrant/healthcheck.sh >> /home/vagrant/azerothcore/logs/health.log 2>&1
CRON
chmod 644 /etc/cron.d/acore-health

validate_external_ip() {
  local ip="$1"

  if [ -z "$ip" ]; then
    return 1
  fi

  python3 - "$ip" <<'PY'
import ipaddress
import sys

try:
    ipaddress.ip_address(sys.argv[1])
except ValueError:
    raise SystemExit(1)
PY
}

start_service_with_retry() {
  local service="$1"
  local retries=5

  while [ "$retries" -gt 0 ]; do
    if systemctl start "$service" && systemctl is-active --quiet "$service"; then
      return 0
    fi

    retries=$((retries - 1))
    if [ "$retries" -le 0 ]; then
      echo "[ERROR] Unable to start $service"
      return 1
    fi

    echo "[WARN] Retrying startup for $service..."
    sleep 3
  done
}

mysql_exec_with_retry() {
  local retries=5

  while [ "$retries" -gt 0 ]; do
    if MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 "$@"; then
      return 0
    fi

    retries=$((retries - 1))
    if [ "$retries" -le 0 ]; then
      echo "[ERROR] MySQL query failed after several attempts"
      return 1
    fi

    echo "[WARN] Retrying MySQL..."
    sleep 2
  done
}

ensure_conf_kv_local() {
  local file="$1"
  local key="$2"
  local value="$3"
  local key_escaped
  local value_escaped

  key_escaped=$(printf '%s' "$key" | sed -e 's/[][\\.^$*+?(){}|]/\\&/g')
  value_escaped=$(printf '%s' "$value" | sed -e 's/[\\&|]/\\&/g')

  if grep -Eq "^[[:space:]]*${key_escaped}[[:space:]]*=" "$file"; then
    sed -i -E "s|^[[:space:]]*${key_escaped}[[:space:]]*=.*|${key} = ${value_escaped}|" "$file"
  else
    printf '\n%s = %s\n' "$key" "$value" >> "$file"
  fi
}

resolve_module_conf_local() {
  local dir="$1"
  shift
  local candidate
  local conf_file
  local conf_base

  for candidate in "$@"; do
    if [ -f "$dir/$candidate" ]; then
      printf '%s\n' "$dir/$candidate"
      return 0
    fi
  done

  shopt -s nullglob
  for conf_file in "$dir"/*.conf; do
    conf_base="$(basename "$conf_file")"
    for candidate in "$@"; do
      if [ "${conf_base,,}" = "${candidate,,}" ]; then
        shopt -u nullglob
        printf '%s\n' "$conf_file"
        return 0
      fi
    done
  done
  shopt -u nullglob

  return 1
}

worldserver_cmd_try() {
  local cmd="$1"
  local soap_port="${SOAP_PORT:-7878}"
  local soap_user="${SOAP_USER:-admin}"
  local soap_pass="${SOAP_PASS:-admin}"
  local payload

  if ! command -v curl >/dev/null 2>&1; then
    echo "[WARN] curl not found: worldserver command skipped: $cmd"
    return 1
  fi

  payload="<?xml version=\"1.0\" encoding=\"utf-8\"?><SOAP-ENV:Envelope xmlns:SOAP-ENV=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:ns1=\"urn:AC\"><SOAP-ENV:Body><ns1:executeCommand><command>${cmd}</command></ns1:executeCommand></SOAP-ENV:Body></SOAP-ENV:Envelope>"

  if curl -fsS --max-time 5 -u "${soap_user}:${soap_pass}" \
      -H 'Content-Type: text/xml; charset=utf-8' \
      -H 'SOAPAction: "urn:AC#executeCommand"' \
      --data "$payload" \
      "http://127.0.0.1:${soap_port}/" >/dev/null 2>&1; then
    echo "[OK] worldserver command executed: $cmd"
    return 0
  fi

  echo "[WARN] worldserver command failed (SOAP): $cmd"
  return 1
}

worldserver_cmd_output() {
  local cmd="$1"
  local soap_port="${SOAP_PORT:-7878}"
  local soap_user="${SOAP_USER:-admin}"
  local soap_pass="${SOAP_PASS:-admin}"
  local payload

  if ! command -v curl >/dev/null 2>&1; then
    return 1
  fi

  payload="<?xml version=\"1.0\" encoding=\"utf-8\"?><SOAP-ENV:Envelope xmlns:SOAP-ENV=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:ns1=\"urn:AC\"><SOAP-ENV:Body><ns1:executeCommand><command>${cmd}</command></ns1:executeCommand></SOAP-ENV:Body></SOAP-ENV:Envelope>"

  curl -fsS --max-time 8 -u "${soap_user}:${soap_pass}" \
    -H 'Content-Type: text/xml; charset=utf-8' \
    -H 'SOAPAction: "urn:AC#executeCommand"' \
    --data "$payload" \
    "http://127.0.0.1:${soap_port}/" 2>/dev/null
}

verify_daily_reset_runtime() {
  local out

  if ! out="$(worldserver_cmd_output ".help daily" || true)"; then
    out=""
  fi

  if printf '%s' "$out" | grep -qi 'daily reset'; then
    echo "[OK] mod-daily-reset active ('.daily reset' command detected)."
  else
    echo "[WARN] mod-daily-reset not confirmed via SOAP (.help daily)."
    echo "[WARN] Check worldserver logs and mod-daily-reset module loading."
  fi
}

get_account_id_by_name() {
  local account_name="$1"
  MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 -Nse \
    "SELECT id FROM acore_auth.account WHERE username=UPPER('${account_name}') LIMIT 1;" 2>/dev/null || true
}

resolve_ahbot_guid_preferred() {
  local account_name="$1"
  local account_id
  local guid
  local guids

  account_id="$(get_account_id_by_name "$account_name")"
  if [ -n "$account_id" ]; then
    guid=$(MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 -Nse \
      "SELECT guid FROM acore_characters.characters WHERE account=${account_id} ORDER BY guid LIMIT 1;" 2>/dev/null || true)
    if [ -n "${guid:-}" ]; then
      printf '%s\n' "$guid"
      return 0
    fi
  fi

  guids=$(MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 -Nse \
    "SELECT GROUP_CONCAT(guid ORDER BY guid SEPARATOR ',') FROM (SELECT guid FROM acore_characters.characters ORDER BY guid LIMIT 3) t;" 2>/dev/null || true)

  if [ -n "${guids:-}" ] && [ "$guids" != "NULL" ]; then
    printf '%s\n' "$guids"
    return 0
  fi

  return 1
}

ensure_ahbot_bootstrap() {
  local account_name="$AHBOT_ACCOUNT_NAME"
  local account_pass="$AHBOT_ACCOUNT_PASS"
  local account_id

  echo "[INFO] Bootstrap AHBot account: account='${account_name}'"

  if /home/vagrant/create-account.sh "$account_name" "$account_pass"; then
    echo "[OK] AHBot account created/updated: ${account_name}"
  else
    echo "[WARN] Failed to create/update AHBot account '${account_name}' (provisioning continues)"
  fi

  account_id="$(get_account_id_by_name "$account_name")"
  if [ -z "$account_id" ]; then
    echo "[WARN] AHBot account not found in auth DB; GUID fallback will be used"
    return 0
  fi

  if MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 -Nse \
      "SELECT 1 FROM acore_characters.characters WHERE account=${account_id} LIMIT 1;" | grep -q 1; then
    echo "[OK] AHBot account already has at least one character."
    return 0
  fi

  echo "[INFO] AHBot account '${account_name}' has no character yet."
  echo "[INFO] Create it with the WoW client, query its GUID, then run: acore-setup-ahbot <guid>"
  echo "[INFO] Until then, AuctionHouseBot.GUIDs will use automatic fallback characters."
}

configure_ahbot_guids() {
  local ahbot_conf
  local guids

  ahbot_conf="$(resolve_module_conf_local "$AC_CONF_DIR/modules" "mod_ahbot.conf" "AuctionHouseBot.conf" "ahbot.conf" || true)"
  if [ -z "${ahbot_conf:-}" ]; then
    echo "[WARN] AHBot config file not found; GUIDs not changed"
    return 0
  fi

  if guids="$(resolve_ahbot_guid_preferred "$AHBOT_ACCOUNT_NAME")"; then
    ensure_conf_kv_local "$ahbot_conf" "AuctionHouseBot.GUIDs" "$guids"
    echo "[OK] AuctionHouseBot.GUIDs configured: $guids"
  else
    echo "[WARN] Unable to resolve AuctionHouseBot.GUIDs; existing value kept"
  fi
}

refresh_ahbot_after_world_up() {
  local attempt

  echo "[INFO] Refreshing AHBot after worldserver startup..."
  worldserver_cmd_try ".ahbot reload" || true

  for attempt in 1 2 3; do
    worldserver_cmd_try ".ahbot update" || true
    sleep 2
  done
}

ensure_transmog_schema() {
  local transmog_sql="/home/vagrant/azerothcore/modules/mod-transmog/data/sql/db-characters/trasmorg.sql"

  if [ ! -f "$transmog_sql" ]; then
    return 0
  fi

  local has_tm has_ua
  has_tm=$(MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 -Nse "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='acore_characters' AND TABLE_NAME='custom_transmogrification';" 2>/dev/null || echo 0)
  has_ua=$(MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 -Nse "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='acore_characters' AND TABLE_NAME='custom_unlocked_appearances';" 2>/dev/null || echo 0)

  if [ "$has_tm" -ge 1 ] && [ "$has_ua" -ge 1 ]; then
    echo "[OK] Transmog schema already present."
    return 0
  fi

  echo "[INFO] Transmog tables missing, importing trasmorg.sql..."
  MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 acore_characters < "$transmog_sql"

  has_tm=$(MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 -Nse "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='acore_characters' AND TABLE_NAME='custom_transmogrification';" 2>/dev/null || echo 0)
  has_ua=$(MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 -Nse "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='acore_characters' AND TABLE_NAME='custom_unlocked_appearances';" 2>/dev/null || echo 0)

  if [ "$has_tm" -ge 1 ] && [ "$has_ua" -ge 1 ]; then
    echo "[OK] Transmog schema repaired."
  else
    echo "[ERROR] Transmog schema fix failed (tables still missing)."
    return 1
  fi
}

resolve_module_sql_file_local() {
  local base_dir="$1"
  shift
  local candidate

  for candidate in "$@"; do
    if [ -f "$base_dir/$candidate" ]; then
      printf '%s\n' "$base_dir/$candidate"
      return 0
    fi
  done

  return 1
}

extract_first_created_table_local() {
  local sql_file="$1"
  awk '
    BEGIN { IGNORECASE=1 }
    /CREATE[[:space:]]+TABLE/ {
      line = $0
      sub(/.*CREATE[[:space:]]+TABLE[[:space:]]+/, "", line)
      sub(/^[[:space:]]*IF[[:space:]]+NOT[[:space:]]+EXISTS[[:space:]]+/, "", line)
      gsub(/`/, "", line)
      split(line, a, /[[:space:](;]/)
      if (a[1] != "") {
        print a[1]
        exit
      }
    }
  ' "$sql_file"
}

extract_script_names_from_sql_local() {
  local sql_file="$1"

  awk '
    BEGIN { IGNORECASE=1 }
    {
      line = $0

      # Pattern 1: ScriptName='foo' (UPDATE/SET style)
      while (match(line, /ScriptName[[:space:]]*=[[:space:]]*'\''[^'\'']+'\''/)) {
        chunk = substr(line, RSTART, RLENGTH)
        sub(/.*'\''/, "", chunk)
        sub(/'\''.*/, "", chunk)
        if (chunk != "") print chunk
        line = substr(line, RSTART + RLENGTH)
      }

      # Pattern 2: INSERT ... ( ..., `ScriptName`, ... ) VALUES ( ..., 'foo', ... )
      if ($0 ~ /INSERT[[:space:]]+INTO/ && $0 ~ /ScriptName/ && $0 ~ /VALUES/) {
        if (match($0, /'\''[^'\'']+'\''[[:space:]]*\)[[:space:]]*;?[[:space:]]*$/)) {
          v = substr($0, RSTART, RLENGTH)
          sub(/^'\''/, "", v)
          sub(/'\''[[:space:]]*\).*/, "", v)
          if (v != "") print v
        }
      }
    }
  ' "$sql_file" | sort -u
}

sql_quote_list_local() {
  local first=1
  local item

  while IFS= read -r item; do
    [ -z "$item" ] && continue
    if [ "$first" -eq 1 ]; then
      printf "'%s'" "${item//\'/\'\'}"
      first=0
    else
      printf ",'%s'" "${item//\'/\'\'}"
    fi
  done
}

ensure_sql_applied_if_missing_local() {
  local db_name="$1"
  local sql_file="$2"
  local scope_label="$3"
  local sentinel_table
  local has_table

  if [ ! -f "$sql_file" ]; then
    echo "[WARN] SQL not found for ${scope_label}: $sql_file"
    return 0
  fi

  sentinel_table="$(extract_first_created_table_local "$sql_file")"
  if [ -z "$sentinel_table" ]; then
    echo "[ERROR] Corrupt SQL (${scope_label}): no CREATE TABLE statement detected in $sql_file"
    return 1
  fi

  has_table=$(MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 -Nse "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='${db_name}' AND TABLE_NAME='${sentinel_table}';" 2>/dev/null || echo 0)
  if [ "$has_table" -ge 1 ]; then
    echo "[OK] ${scope_label}: schema already present (${db_name}.${sentinel_table})."
    return 0
  fi

  echo "[INFO] ${scope_label}: schema missing, importing $(basename "$sql_file")..."
  MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 "$db_name" < "$sql_file"

  has_table=$(MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 -Nse "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='${db_name}' AND TABLE_NAME='${sentinel_table}';" 2>/dev/null || echo 0)
  if [ "$has_table" -ge 1 ]; then
    echo "[OK] ${scope_label}: schema repaired (${db_name}.${sentinel_table})."
    return 0
  fi

  echo "[ERROR] ${scope_label}: SQL import had no effect (sentinel table ${db_name}.${sentinel_table} missing)."
  return 1
}

ensure_world_sql_applied_for_module_local() {
  local sql_file="$1"
  local scope_label="$2"
  local probe_sql="$3"
  local expected_min="$4"
  local probe_count

  if [ ! -f "$sql_file" ]; then
    echo "[WARN] World SQL not found for ${scope_label}: $sql_file"
    return 0
  fi

  probe_count=$(MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 -Nse "$probe_sql" 2>/dev/null || echo 0)
  if [ "$probe_count" -ge "$expected_min" ]; then
    echo "[OK] ${scope_label}: world data already present (${probe_count} >= ${expected_min})."
    return 0
  fi

  echo "[INFO] ${scope_label}: module appears inactive (${probe_count} < ${expected_min}), importing $(basename "$sql_file")..."
  MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 acore_world < "$sql_file"

  probe_count=$(MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 -Nse "$probe_sql" 2>/dev/null || echo 0)
  if [ "$probe_count" -ge "$expected_min" ]; then
    echo "[OK] ${scope_label}: world data repaired (${probe_count} >= ${expected_min})."
    return 0
  fi

  echo "[ERROR] ${scope_label}: SQL import had no effect (${probe_count} < ${expected_min})."
  return 1
}

ensure_module_runtime_repairs() {
  local reagent_base="/home/vagrant/azerothcore/modules/mod-reagent-bank-account/data/sql"
  local transmog_world_base="/home/vagrant/azerothcore/modules/mod-transmog/data/sql/db-world"
  local reagent_world_sql
  local reagent_char_sql
  local transmog_world_sql

  reagent_world_sql="$(resolve_module_sql_file_local "$reagent_base/db-world" \
    "base/mod_reagent_bank_account_NPC.sql" \
    "mod_reagent_bank_account_NPC.sql" \
    "base/reagent_bank_account_world.sql" \
    "reagent_bank_account_world.sql" || true)"
  reagent_char_sql="$(resolve_module_sql_file_local "$reagent_base/db-characters" \
    "base/mod_reagent_bank_account_create_table.sql" \
    "mod_reagent_bank_account_create_table.sql" \
    "base/reagent_bank_account_characters.sql" \
    "reagent_bank_account_characters.sql" || true)"

  transmog_world_sql="$(resolve_module_sql_file_local "$transmog_world_base" \
    "trasm_world_NPC.sql" \
    "transmog_npc.sql" \
    "transmog.sql" \
    "mod_transmog_world.sql" \
    "world.sql" || true)"

  # Reagent bank: characters schema + world data/module activation
  ensure_sql_applied_if_missing_local "acore_characters" "$reagent_char_sql" "mod-reagent-bank-account (characters)"
  ensure_world_sql_applied_for_module_local "$reagent_world_sql" "mod-reagent-bank-account" \
    "SELECT COUNT(*) FROM acore_world.creature_template WHERE ScriptName LIKE '%reagent%' OR name LIKE '%Reagent%';" \
    1

  # Transmog: ensure NPC script assignment from world SQL
  ensure_world_sql_applied_for_module_local "$transmog_world_sql" "mod-transmog NPC" \
    "SELECT COUNT(*) FROM acore_world.creature_template WHERE ScriptName='npc_transmogrifier';" \
    1
}

ensure_module_strings() {
  MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 acore_world -e "INSERT INTO module_string (module,id,string) VALUES ('mod-aoe-loot',1,'Aoe Loot') ON DUPLICATE KEY UPDATE string=VALUES(string);" 2>/dev/null || true
}

wait_for_worldserver_console() {
  local retries=120

  echo "Waiting for worldserver availability (max 360s)..."
  while [ $retries -gt 0 ]; do
    if systemctl is-active --quiet acore-world && ss -ltn 2>/dev/null | grep -q ':8085 '; then
      echo "[OK] worldserver port detected (8085)."
      return 0
    fi

    echo -n "."
    sleep 3
    retries=$((retries - 1))
  done

  echo ""
  echo "[WARN] Worldserver not reliably detected after 360s."
  return 1
}

wait_for_soap_ready() {
  local retries=100
  local out

  echo "Waiting for worldserver SOAP availability (max 300s)..."
  while [ $retries -gt 0 ]; do
    if ss -ltn 2>/dev/null | grep -q ':7878 '; then
      out="$(worldserver_cmd_output ".server info" || true)"
      if [ -n "${out:-}" ] && printf '%s' "$out" | grep -qi 'executeCommandResponse'; then
        echo "[OK] worldserver SOAP available."
        return 0
      fi
    fi

    echo -n "."
    sleep 3
    retries=$((retries - 1))
  done

  echo ""
  echo "[WARN] worldserver SOAP unavailable after 300s."
  return 1
}

echo "========================================"
echo "Finalization & Admin"
echo "========================================"

start_service_with_retry acore-auth
ensure_transmog_schema
ensure_module_runtime_repairs
ensure_module_strings
start_service_with_retry acore-world

wait_for_worldserver_console || true

echo "Creating 'admin' account..."
if MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 acore_auth -Nse "SELECT 1 FROM account WHERE username='admin' LIMIT 1;" | grep -q 1; then
  echo "[OK] Admin account already present."
else
  sleep 3
  if /home/vagrant/create-account.sh admin admin && /home/vagrant/set-gm.sh admin 3 -1; then
    echo "[OK] Admin account created and GM rights applied via DB scripts."
  else
    echo "[WARN] Automatic admin account creation skipped. Run ./create-account.sh then ./set-gm.sh manually."
  fi
fi

ensure_ahbot_bootstrap
configure_ahbot_guids
if wait_for_soap_ready; then
  verify_daily_reset_runtime
  refresh_ahbot_after_world_up
else
  echo "[WARN] mod-daily-reset verification and AHBot refresh skipped (SOAP unavailable)."
fi

echo "========================================"
echo "Configuring realm"
echo "========================================"

EXT_IP="${EXTERNAL_IP:-}"

if [ -z "$EXT_IP" ]; then
  echo "[WARN] EXTERNAL_IP not set: external realm not changed (provisioning continues)"
elif ! validate_external_ip "$EXT_IP"; then
  echo "[WARN] Invalid EXTERNAL_IP ('$EXT_IP'): external realm not changed (provisioning continues)"
else
  mysql_exec_with_retry acore_auth -e "UPDATE realmlist SET address='$EXT_IP', localAddress='127.0.0.1', localSubnetMask='255.255.255.0' WHERE id=1;"
  mysql_exec_with_retry acore_auth -e "DELETE FROM realmlist WHERE id=2;"
  echo "[OK] Realm configured ($EXT_IP / Local)"
fi
echo "========================================"
echo "Installation completed successfully!"
echo "========================================"
