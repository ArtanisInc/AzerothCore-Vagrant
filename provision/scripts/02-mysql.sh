#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

echo "========================================"
echo "Installing MySQL 8.x"
echo "========================================"

export DEBIAN_FRONTEND="noninteractive"
apt-get update -qq
apt-get install -y mysql-server libmysqlclient-dev

wait_for_mysql() {
  local retries=30

  until mysqladmin ping -u root --protocol=socket >/dev/null 2>&1; do
    retries=$((retries - 1))
    if [ "$retries" -le 0 ]; then
      echo "[ERROR] MySQL did not start within the timeout"
      return 1
    fi

    echo "Waiting for MySQL..."
    sleep 2
  done
}

mysql_size_to_mb() {
  local value="$1"
  local number
  local unit

  value="${value//[[:space:]]/}"
  number="${value%[KkMmGg]}"
  unit="${value:${#number}}"

  if ! [[ "$number" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  case "$unit" in
    G|g) echo $((number * 1024)) ;;
    M|m|'') echo "$number" ;;
    K|k) echo $((number / 1024)) ;;
    *) return 1 ;;
  esac
}

calculate_mysql_memory_settings() {
  local vm_ram_mb="${VM_RAM:-8192}"
  local pool_mb
  local instances
  local log_mb

  if ! [[ "$vm_ram_mb" =~ ^[0-9]+$ ]] || [ "$vm_ram_mb" -lt 1024 ]; then
    vm_ram_mb=8192
  fi

  if [ -n "${MYSQL_INNODB_BUFFER_POOL_SIZE:-}" ]; then
    if ! pool_mb="$(mysql_size_to_mb "$MYSQL_INNODB_BUFFER_POOL_SIZE")" || [ "$pool_mb" -lt 128 ]; then
      echo "[ERROR] Invalid MYSQL_INNODB_BUFFER_POOL_SIZE: $MYSQL_INNODB_BUFFER_POOL_SIZE"
      exit 1
    fi
  else
    # Keep RAM available for the build, worldserver, authserver, and OS cache.
    pool_mb=$((vm_ram_mb * 50 / 100))
    if [ "$pool_mb" -lt 512 ]; then
      pool_mb=512
    fi
    if [ "$pool_mb" -gt $((vm_ram_mb - 2048)) ] && [ "$vm_ram_mb" -gt 3072 ]; then
      pool_mb=$((vm_ram_mb - 2048))
    fi
  fi

  instances="${MYSQL_INNODB_BUFFER_POOL_INSTANCES:-$((pool_mb / 1024))}"
  if ! [[ "$instances" =~ ^[0-9]+$ ]] || [ "$instances" -lt 1 ]; then
    instances=1
  fi
  if [ "$instances" -gt 8 ]; then
    instances=8
  fi

  log_mb="${MYSQL_INNODB_LOG_FILE_SIZE_MB:-$((pool_mb / 4))}"
  if ! [[ "$log_mb" =~ ^[0-9]+$ ]] || [ "$log_mb" -lt 256 ]; then
    log_mb=256
  fi
  if [ "$log_mb" -gt 1536 ]; then
    log_mb=1536
  fi

  MYSQL_BUFFER_POOL_SIZE="${pool_mb}M"
  MYSQL_BUFFER_POOL_INSTANCES="$instances"
  MYSQL_LOG_FILE_SIZE="${log_mb}M"
}

calculate_mysql_memory_settings

# Base MySQL configuration
mkdir -p /etc/mysql/mysql.conf.d
cat > /etc/mysql/mysql.conf.d/acore.cnf <<MYSQL_CONF
[mysqld]
bind-address = 127.0.0.1
disable_log_bin
innodb_buffer_pool_size = ${MYSQL_BUFFER_POOL_SIZE}
innodb_buffer_pool_instances = ${MYSQL_BUFFER_POOL_INSTANCES}
innodb_log_file_size = ${MYSQL_LOG_FILE_SIZE}
innodb_log_buffer_size = 64M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
innodb_io_capacity = 800
innodb_io_capacity_max = 1600
innodb_read_io_threads = 4
innodb_write_io_threads = 4
innodb_file_per_table = 1
max_connections = 200
thread_cache_size = 50
table_open_cache = 4000
max_allowed_packet = 64M
sort_buffer_size = 512K
join_buffer_size = 512K
read_buffer_size = 256K
read_rnd_buffer_size = 512K
default_storage_engine = InnoDB
MYSQL_CONF

echo "[OK] MySQL memory: VM_RAM=${VM_RAM:-8192}M buffer_pool=${MYSQL_BUFFER_POOL_SIZE} instances=${MYSQL_BUFFER_POOL_INSTANCES} log_file=${MYSQL_LOG_FILE_SIZE}"

echo "--- Starting MySQL ---"
systemctl restart mysql
wait_for_mysql

echo "--- Configuring privileges ---"
DB_PASS_SQL="$(printf "%s" "$DB_PASS" | sed "s/'/''/g")"
mysql -u root <<SQL_SCRIPT
DROP USER IF EXISTS 'acore'@'localhost';
DROP USER IF EXISTS 'acore'@'%';
CREATE USER 'acore'@'localhost' IDENTIFIED WITH mysql_native_password BY '${DB_PASS_SQL}';
CREATE DATABASE IF NOT EXISTS acore_auth DEFAULT CHARACTER SET utf8mb4;
CREATE DATABASE IF NOT EXISTS acore_characters DEFAULT CHARACTER SET utf8mb4;
CREATE DATABASE IF NOT EXISTS acore_world DEFAULT CHARACTER SET utf8mb4;
CREATE DATABASE IF NOT EXISTS acore_playerbots DEFAULT CHARACTER SET utf8mb4;
GRANT ALL PRIVILEGES ON acore_auth.* TO 'acore'@'localhost';
GRANT ALL PRIVILEGES ON acore_characters.* TO 'acore'@'localhost';
GRANT ALL PRIVILEGES ON acore_world.* TO 'acore'@'localhost';
GRANT ALL PRIVILEGES ON acore_playerbots.* TO 'acore'@'localhost';
FLUSH PRIVILEGES;
SQL_SCRIPT

echo "--- Connection test (simple format) ---"
if MYSQL_PWD="$DB_PASS" mysql -uacore -h 127.0.0.1 -e "SELECT 1" >/dev/null 2>&1; then
  echo "[OK] MySQL connection succeeded"
else
  echo "[ERROR] Connection failed"
  mysql -u root --protocol=socket -e "SELECT User, Host, plugin FROM mysql.user WHERE User='acore';"
  exit 1
fi
