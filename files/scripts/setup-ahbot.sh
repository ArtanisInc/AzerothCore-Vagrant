#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

echo "Configuration de AHBot-Plus..."
echo "--- IMPORTANT: Vous devez avoir cree des personnages pour le bot ---"
read -p "Entrez les GUIDs des personnages (separes par des virgules) : " GUIDS

if [ -n "$GUIDS" ]; then
    if grep -q '^AuctionHouseBot.GUIDs' "$AC_CONF_DIR/worldserver.conf"; then
        sed -i "s/^AuctionHouseBot.GUIDs.*/AuctionHouseBot.GUIDs = $GUIDS/" "$AC_CONF_DIR/worldserver.conf"
    elif grep -q '^AuctionHouseBot.Buyer.Enabled' "$AC_CONF_DIR/worldserver.conf"; then
        awk -v guids="$GUIDS" '
            {
                print
                if ($0 ~ /^AuctionHouseBot\.Buyer\.Enabled/ && !inserted) {
                    print ""
                    print "# GUIDs des personnages AHBot (depuis table '\''characters'\'')"
                    print "# IMPORTANT: Utiliser des vrais personnages, PAS des Playerbots!"
                    print "# Configurer avec: ./setup-ahbot.sh"
                    print "AuctionHouseBot.GUIDs = " guids
                    inserted=1
                }
            }
        ' "$AC_CONF_DIR/worldserver.conf" > "$AC_CONF_DIR/worldserver.conf.tmp"
        mv "$AC_CONF_DIR/worldserver.conf.tmp" "$AC_CONF_DIR/worldserver.conf"
    else
        printf '\nAuctionHouseBot.GUIDs = %s\n' "$GUIDS" >> "$AC_CONF_DIR/worldserver.conf"
    fi
    echo "[OK] GUIDs mis a jour. Redemarrez le serveur."
else
    echo "Annule."
fi
