#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

echo "Configuring AHBot-Plus..."
echo "--- IMPORTANT: You must have created characters for the bot ---"
read -p "Enter character GUIDs (comma-separated): " GUIDS

if [ -n "$GUIDS" ]; then
    if grep -q '^AuctionHouseBot.GUIDs' "$AC_CONF_DIR/worldserver.conf"; then
        sed -i "s/^AuctionHouseBot.GUIDs.*/AuctionHouseBot.GUIDs = $GUIDS/" "$AC_CONF_DIR/worldserver.conf"
    elif grep -q '^AuctionHouseBot.Buyer.Enabled' "$AC_CONF_DIR/worldserver.conf"; then
        awk -v guids="$GUIDS" '
            {
                print
                if ($0 ~ /^AuctionHouseBot\.Buyer\.Enabled/ && !inserted) {
                    print ""
                    print "# AHBot character GUIDs (from the '\''characters'\'' table)"
                    print "# IMPORTANT: Use real characters, NOT Playerbots!"
                    print "# Configure with: ./setup-ahbot.sh"
                    print "AuctionHouseBot.GUIDs = " guids
                    inserted=1
                }
            }
        ' "$AC_CONF_DIR/worldserver.conf" > "$AC_CONF_DIR/worldserver.conf.tmp"
        mv "$AC_CONF_DIR/worldserver.conf.tmp" "$AC_CONF_DIR/worldserver.conf"
    else
        printf '\nAuctionHouseBot.GUIDs = %s\n' "$GUIDS" >> "$AC_CONF_DIR/worldserver.conf"
    fi
    echo "[OK] GUIDs updated. Restart the server."
else
    echo "Cancelled."
fi
