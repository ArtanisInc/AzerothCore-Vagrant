#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

echo "========================================"
echo "Installation de MySQL 8.x"
echo "========================================"

export DEBIAN_FRONTEND="noninteractive"
apt-get update -qq
apt-get install -y mysql-server libmysqlclient-dev

wait_for_mysql() {
  local retries=30

  until mysqladmin ping -u root --protocol=socket >/dev/null 2>&1; do
    retries=$((retries - 1))
    if [ "$retries" -le 0 ]; then
      echo "[ERROR] MySQL n'a pas demarre dans le delai imparti"
      return 1
    fi

    echo "Attente de MySQL..."
    sleep 2
  done
}

# Configuration MySQL de base
mkdir -p /etc/mysql/mysql.conf.d
cat > /etc/mysql/mysql.conf.d/acore.cnf <<'MYSQL_CONF'
[mysqld]
bind-address = 127.0.0.1
disable_log_bin
innodb_buffer_pool_size = 8G
innodb_buffer_pool_instances = 8
innodb_log_file_size = 1536M
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

echo "--- Demarrage de MySQL ---"
systemctl restart mysql
wait_for_mysql

echo "--- Configuration des privileges ---"
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

echo "--- Test de connexion (Format simple) ---"
if MYSQL_PWD="$DB_PASS" mysql -uacore -h 127.0.0.1 -e "SELECT 1" >/dev/null 2>&1; then
  echo "[OK] Connexion MySQL reussie"
else
  echo "[ERROR] Echec de connexion"
  mysql -u root --protocol=socket -e "SELECT User, Host, plugin FROM mysql.user WHERE User='acore';"
  exit 1
fi
