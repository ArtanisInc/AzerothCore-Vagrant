#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
    echo "Usage: acore-set-gm <username> <gmlevel> [realmId]"
    echo "Example: acore-set-gm admin 3 -1"
    exit 1
fi

username="$1"
gmlevel="$2"
realm_id="${3:--1}"

if ! [[ "$username" =~ ^[A-Za-z0-9_]{1,16}$ ]]; then
    echo "[ERROR] invalid username. Use only [A-Za-z0-9_] (1-16 chars)."
    exit 1
fi

if ! [[ "$gmlevel" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] gmlevel must be an integer >= 0"
    exit 1
fi

if ! [[ "$realm_id" =~ ^-?[0-9]+$ ]]; then
    echo "[ERROR] realmId must be an integer (e.g. -1, 1, 2...)"
    exit 1
fi

username_sql="$(printf "%s" "$username" | sed "s/'/''/g")"

echo "Assigning GM level $gmlevel to '$username' (RealmID=$realm_id)..."

account_id=$(MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 acore_auth -Nse "SELECT id FROM account WHERE username=UPPER('$username_sql') LIMIT 1;" || true)

if [ -z "$account_id" ]; then
    echo "[ERROR] Account not found: $username"
    echo "Create it first with: acore-create-account <username> <password>"
    exit 1
fi

MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 acore_auth -e "INSERT INTO account_access (id, gmlevel, RealmID) VALUES ('$account_id', '$gmlevel', '$realm_id') ON DUPLICATE KEY UPDATE gmlevel=VALUES(gmlevel), RealmID=VALUES(RealmID);"

echo "[OK] GM rights applied: user=$username id=$account_id level=$gmlevel realm=$realm_id"
