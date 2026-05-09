#!/bin/bash
set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${DB_BACKUP_DIR:-/home/vagrant/backups}"
BACKUP_RETENTION="${DB_BACKUP_RETENTION:-7}"
DB_HOST_BACKUP="${DB_HOST:-127.0.0.1}"

if ! [[ "$BACKUP_RETENTION" =~ ^[0-9]+$ ]]; then
  echo "[ERROR] DB_BACKUP_RETENTION must be an integer."
  exit 1
fi

mkdir -p "$BACKUP_DIR"

echo "Backing up databases..."
echo "Destination: $BACKUP_DIR"
echo "Retention: $BACKUP_RETENTION backup(s) per database"

mysql_db_exists() {
  local db="$1"
  local result

  if ! result="$(MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h "$DB_HOST_BACKUP" -Nse \
    "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='${db}' LIMIT 1;")"; then
    echo "[ERROR] MySQL connection failed or verification query failed for: $db"
    exit 1
  fi

  [ "$result" = "$db" ]
}

backup_database() {
  local db="$1"
  local out="$BACKUP_DIR/${db}_${DATE}.sql.gz"
  local tmp="${out}.tmp"

  if ! mysql_db_exists "$db"; then
    echo "[WARN] Database missing, skipped: $db"
    return 0
  fi

  echo " - $db -> $out"
  rm -f "$tmp"
  if MYSQL_PWD="$DB_PASS" mysqldump \
    -u "$DB_USER" \
    -h "$DB_HOST_BACKUP" \
    --single-transaction \
    --quick \
    --routines \
    --triggers \
    "$db" | gzip -9 > "$tmp"; then
    mv "$tmp" "$out"
  else
    rm -f "$tmp"
    echo "[ERROR] Backup failed: $db"
    return 1
  fi
}

rotate_database_backups() {
  local db="$1"

  if [ "$BACKUP_RETENTION" -eq 0 ]; then
    return 0
  fi

  find "$BACKUP_DIR" -maxdepth 1 -type f -name "${db}_*.sql.gz" \
    | sort -r \
    | tail -n +"$((BACKUP_RETENTION + 1))" \
    | while IFS= read -r old_backup; do
        rm -f "$old_backup"
        echo "   removed old backup: $(basename "$old_backup")"
      done
}

databases=(
  acore_auth
  acore_characters
  acore_world
  acore_playerbots
)

for db in "${databases[@]}"; do
  backup_database "$db"
  rotate_database_backups "$db"
done

echo "[OK] Compressed backup completed in $BACKUP_DIR"
