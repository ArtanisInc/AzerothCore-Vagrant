#!/bin/bash
set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/home/vagrant/backups"
mkdir -p "$BACKUP_DIR"

echo "Sauvegarde des bases de donnees..."
MYSQL_PWD="$DB_PASS" mysqldump -u "$DB_USER" acore_auth > "$BACKUP_DIR/auth_${DATE}.sql"
MYSQL_PWD="$DB_PASS" mysqldump -u "$DB_USER" acore_characters > "$BACKUP_DIR/chars_${DATE}.sql"
MYSQL_PWD="$DB_PASS" mysqldump -u "$DB_USER" acore_world > "$BACKUP_DIR/world_${DATE}.sql"

echo "[OK] Sauvegarde terminee dans $BACKUP_DIR"
