#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
    echo "Usage: acore-create-account <username> <password>"
    exit 1
fi

if ! pgrep -x "worldserver" >/dev/null 2>&1; then
    echo "[ERROR] Process worldserver introuvable."
    echo "Attendez que le service soit disponible (acore-status / acore-health), puis reessayez."
    exit 1
fi

username="$1"
password="$2"

if ! [[ "$username" =~ ^[A-Za-z0-9_]{1,16}$ ]]; then
    echo "[ERROR] username invalide. Utilisez uniquement [A-Za-z0-9_] (1-16 chars)."
    exit 1
fi

username_sql="$(printf "%s" "$username" | sed "s/'/''/g")"
password_sql="$(printf "%s" "$password" | sed "s/'/''/g")"

echo "Creation du compte '$username' via DB auth..."

# Detect schema flavor (legacy sha_pass_hash vs SRP6 salt/verifier)
has_sha_pass_hash=$(MYSQL_PWD="$DB_PASS" mysql -Nse "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='acore_auth' AND TABLE_NAME='account' AND COLUMN_NAME='sha_pass_hash';" -u "$DB_USER" -h 127.0.0.1 || echo 0)
has_srp6=$(MYSQL_PWD="$DB_PASS" mysql -Nse "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='acore_auth' AND TABLE_NAME='account' AND COLUMN_NAME IN ('salt','verifier');" -u "$DB_USER" -h 127.0.0.1 || echo 0)

if [ "$has_sha_pass_hash" -ge 1 ]; then
    MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 acore_auth -e "INSERT INTO account (username, sha_pass_hash, reg_mail, email) VALUES (UPPER('$username_sql'), SHA1(CONCAT(UPPER('$username_sql'), ':', UPPER('$password_sql'))), '', '') ON DUPLICATE KEY UPDATE sha_pass_hash=VALUES(sha_pass_hash);"
elif [ "$has_srp6" -ge 2 ]; then
    read -r salt_hex verifier_hex < <(python3 - "$username" "$password" <<'PY'
import hashlib
import secrets
import sys

username = sys.argv[1].upper()
password = sys.argv[2].upper()

# AzerothCore SRP6 params
g = 7
N = int('894B645E89E1535BBDAD5B8B290650530801B18EBFBF5E8FAB3C82872A3E9BB7', 16)

h1 = hashlib.sha1(f"{username}:{password}".encode()).digest()
salt = secrets.token_bytes(32)
h2 = hashlib.sha1(salt + h1).digest()
x = int.from_bytes(h2, byteorder='little', signed=False)
verifier_int = pow(g, x, N)
verifier = verifier_int.to_bytes(32, byteorder='little', signed=False)

print(salt.hex(), verifier.hex())
PY
)

    MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 acore_auth -e "INSERT INTO account (username, salt, verifier, reg_mail, email) VALUES (UPPER('$username_sql'), UNHEX('$salt_hex'), UNHEX('$verifier_hex'), '', '') ON DUPLICATE KEY UPDATE salt=VALUES(salt), verifier=VALUES(verifier);"
else
    echo "[ERROR] Schema account non reconnu: ni sha_pass_hash ni salt/verifier detectes."
    exit 1
fi

echo "[OK] Compte cree/mis a jour: $username"
echo "[INFO] Attribuez les droits GM si besoin via SQL sur acore_auth.account_access."
