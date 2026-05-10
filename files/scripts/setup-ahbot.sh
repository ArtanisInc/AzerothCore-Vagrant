#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

echo "Configuring AHBot-Plus..."
echo "--- IMPORTANT: AHBot requires existing character GUIDs ---"
echo "--- Recommended: log in as ${AHBOT_ACCOUNT_NAME:-ahbot}, create a dedicated AHBot character, then query its GUID. ---"

GUIDS="${1:-}"
if [ -z "$GUIDS" ]; then
    read -p "Enter character GUIDs (comma-separated): " GUIDS
fi

if [ -n "$GUIDS" ]; then
    if ! printf '%s' "$GUIDS" | grep -Eq '^[0-9]+(,[0-9]+)*$'; then
        echo "[ERROR] Invalid GUID list: $GUIDS"
        echo "Expected format: 123 or 123,456"
        exit 1
    fi

    AHBOT_CONF=""
    for candidate in mod_ahbot.conf AuctionHouseBot.conf ahbot.conf; do
        if [ -f "$AC_CONF_DIR/modules/$candidate" ]; then
            AHBOT_CONF="$AC_CONF_DIR/modules/$candidate"
            break
        fi
    done

    if [ -z "$AHBOT_CONF" ]; then
        echo "[ERROR] AHBot module config not found in $AC_CONF_DIR/modules"
        exit 1
    fi

    if grep -q '^AuctionHouseBot.GUIDs' "$AHBOT_CONF"; then
        sed -i "s/^AuctionHouseBot.GUIDs.*/AuctionHouseBot.GUIDs = $GUIDS/" "$AHBOT_CONF"
    else
        printf '\nAuctionHouseBot.GUIDs = %s\n' "$GUIDS" >> "$AHBOT_CONF"
    fi

    echo "[OK] AHBot GUIDs updated in $AHBOT_CONF"
    echo "[INFO] Restart worldserver or run: sudo systemctl restart acore-world"
else
    echo "Cancelled."
fi
