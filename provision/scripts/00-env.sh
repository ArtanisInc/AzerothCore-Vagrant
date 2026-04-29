#!/bin/bash

set -Eeuo pipefail

# Common variables for AzerothCore provisioning
ENV_FILE="/vagrant/.env"

generate_secret() {
    local uuid
    uuid="$(cat /proc/sys/kernel/random/uuid)"
    uuid="${uuid//-/}"
    printf '%s' "${uuid:0:24}"
}

persist_env_value() {
    local key="$1"
    local value="$2"
    local tmp

    if [ ! -f "$ENV_FILE" ]; then
        return 0
    fi

    tmp="$(mktemp)"
    awk -v key="$key" -v value="$value" '
        BEGIN { found = 0 }
        {
            if ($0 ~ "^[[:space:]]*" key "=") {
                print key "=" value
                found = 1
            } else {
                print
            }
        }
        END {
            if (!found) {
                print key "=" value
            }
        }
    ' "$ENV_FILE" > "$tmp"
    mv "$tmp" "$ENV_FILE"
}

# Source .env if present in /vagrant (with CRLF to LF protection)
if [ -f "$ENV_FILE" ]; then
    echo "Sourcing environment from $ENV_FILE"
    while IFS= read -r line; do
        line="${line#${line%%[![:space:]]*}}"
        case "$line" in
            ''|'#'*)
                continue
                ;;
        esac

        key="${line%%=*}"
        value="${line#*=}"
        if [ -n "$key" ]; then
            export "$key=$value"
        fi
    done < <(tr -d '\r' < "$ENV_FILE")
fi

# Default directory definitions (can be overridden by .env)
export AC_CODE_DIR="${AC_CODE_DIR:-/home/vagrant/azerothcore}"
export AC_INSTALL_DIR="${AC_INSTALL_DIR:-$AC_CODE_DIR/env/dist}"
export AC_BIN_DIR="${AC_INSTALL_DIR}/bin"
export AC_CONF_DIR="${AC_INSTALL_DIR}/etc"
export AC_LOG_DIR="${AC_CODE_DIR}/logs"

# Default Database definitions
export DB_USER="${DB_USER:-acore}"
export DB_PASS="${DB_PASS:-}"
export DB_HOST="${DB_HOST:-localhost}"

if [ -z "$DB_PASS" ] || [ "$DB_PASS" = "acore" ]; then
    DB_PASS="$(generate_secret)"
    export DB_PASS
    persist_env_value "DB_PASS" "$DB_PASS"
fi

# Default Source definitions
export ACORE_REPO="${ACORE_REPO:-https://github.com/mod-playerbots/azerothcore-wotlk.git}"
export ACORE_BRANCH="${ACORE_BRANCH:-Playerbot}"
