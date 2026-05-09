#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

echo "========================================"
echo "Cloning AzerothCore source code"
echo "========================================"

clone_repo_ref() {
  local url="$1"
  local dest="$2"
  local ref="${3:-}"

  if [ -d "$dest/.git" ]; then
    echo "[OK] Repository already present."
    return 0
  fi

  if [ -z "$ref" ]; then
    echo "Cloning repository (default branch)..."
    git clone --depth 1 "$url" "$dest"
  else
    echo "Cloning repository (ref $ref)..."
    git init "$dest"
    git -C "$dest" remote add origin "$url"
    git -C "$dest" fetch --depth 1 origin "$ref"
    git -C "$dest" checkout --detach FETCH_HEAD
  fi

  echo "[OK] Repository cloned successfully."
}

clone_repo_ref "$ACORE_REPO" "$AC_CODE_DIR" "${ACORE_REF:-$ACORE_BRANCH}"

echo "========================================"
echo "Installing modules"
echo "========================================"

mkdir -p "$AC_CODE_DIR/modules"

modules=(
  "mod-playerbots;https://github.com/mod-playerbots/mod-playerbots.git;${MOD_PLAYERBOTS_REF:-}"
  "mod-ah-bot-plus;https://github.com/NathanHandley/mod-ah-bot-plus.git;${MOD_AH_BOT_PLUS_REF:-}"
  "mod-autobalance;https://github.com/azerothcore/mod-autobalance.git;${MOD_AUTOBALANCE_REF:-}"
  "mod-aoe-loot;https://github.com/azerothcore/mod-aoe-loot.git;${MOD_AOE_LOOT_REF:-}"
  "mod-learn-spells;https://github.com/azerothcore/mod-learn-spells.git;${MOD_LEARN_SPELLS_REF:-}"
  "mod-solo-lfg;https://github.com/azerothcore/mod-solo-lfg.git;${MOD_SOLO_LFG_REF:-}"
  "mod-challenge-modes;https://github.com/ZhengPeiRu21/mod-challenge-modes.git;${MOD_CHALLENGE_MODES_REF:-}"
  "mod-player-bot-level-brackets;https://github.com/kadeshar/mod-player-bot-level-brackets.git;${MOD_PLAYER_BOT_LEVEL_BRACKETS_REF:-}"
  "mod-junk-to-gold;https://github.com/kadeshar/mod-junk-to-gold.git;${MOD_JUNK_TO_GOLD_REF:-}"
  "mod-rare-drops;https://github.com/ArtanisInc/mod-rare-drops.git;${MOD_RARE_DROPS_REF:-fix}"
  "mod-transmog;https://github.com/azerothcore/mod-transmog.git;${MOD_TRANSMOG_REF:-}"
  "mod-reagent-bank-account;https://github.com/Brian-Aldridge/mod-reagent-bank-account.git;${MOD_REAGENT_BANK_ACCOUNT_REF:-}"
  "mod-daily-reset;https://github.com/binboupan/mod-daily-reset.git;${MOD_DAILY_RESET_REF:-}"
  "mod-fly-anywhere;https://github.com/abracadaniel22/mod-fly-anywhere.git;${MOD_FLY_ANYWHERE_REF:-}"
  "portals-in-all-capitals;https://github.com/azerothcore/portals-in-all-capitals.git;${MOD_PORTALS_IN_ALL_CAPITALS_REF:-}"
)

for item in "${modules[@]}"; do
    IFS=";" read -r name url ref <<< "$item"
    if [ ! -d "$AC_CODE_DIR/modules/$name/.git" ]; then
      clone_repo_ref "$url" "$AC_CODE_DIR/modules/$name" "$ref" || {
        echo "[WARN] Failed to clone $name"
        continue
      }
      echo "[OK] Module $name cloned."
    else
      echo "[OK] Module $name already present."
    fi
done
