#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

echo "Updating source code..."
cd "$AC_CODE_DIR"
if [ -n "${ACORE_REF:-}" ]; then
    git fetch --depth 1 origin "$ACORE_REF"
    git checkout --detach FETCH_HEAD
else
    git pull --ff-only origin "$ACORE_BRANCH"
fi

echo "Updating modules..."
cd modules
for d in */; do
    if [ -d "$d/.git" ]; then
        echo "Updating $d..."
        case "$d" in
            mod-playerbots/)
                ref="${MOD_PLAYERBOTS_REF:-}"
                ;;
            mod-ah-bot-plus/)
                ref="${MOD_AH_BOT_PLUS_REF:-}"
                ;;
            mod-autobalance/)
                ref="${MOD_AUTOBALANCE_REF:-}"
                ;;
            mod-aoe-loot/)
                ref="${MOD_AOE_LOOT_REF:-}"
                ;;
            mod-learn-spells/)
                ref="${MOD_LEARN_SPELLS_REF:-}"
                ;;
            mod-solo-lfg/)
                ref="${MOD_SOLO_LFG_REF:-}"
                ;;
            mod-challenge-modes/)
                ref="${MOD_CHALLENGE_MODES_REF:-}"
                ;;
            mod-rare-drops/)
                ref="${MOD_RARE_DROPS_REF:-fix}"
                ;;
            mod-player-bot-level-brackets/)
                ref="${MOD_PLAYER_BOT_LEVEL_BRACKETS_REF:-}"
                ;;
            mod-junk-to-gold/)
                ref="${MOD_JUNK_TO_GOLD_REF:-}"
                ;;
            mod-transmog/)
                ref="${MOD_TRANSMOG_REF:-}"
                ;;
            portals-in-all-capitals/)
                ref="${MOD_PORTALS_IN_ALL_CAPITALS_REF:-}"
                ;;
            *)
                ref=""
                ;;
        esac

        if [ -n "$ref" ]; then
            git -C "$d" fetch --depth 1 origin "$ref"
            git -C "$d" checkout --detach FETCH_HEAD
        else
            git -C "$d" pull --ff-only
        fi
    fi
done

echo "[OK] Update complete. Recompile if needed."
