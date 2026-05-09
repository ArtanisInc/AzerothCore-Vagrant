#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

ensure_conf_kv() {
    local file="$1"
    local key="$2"
    local value="$3"
    local key_escaped
    local value_escaped

    key_escaped=$(printf '%s' "$key" | sed -e 's/[][\\.^$*+?(){}|]/\\&/g')
    value_escaped=$(printf '%s' "$value" | sed -e 's/[\\&|]/\\&/g')

    if grep -Eq "^[[:space:]]*${key_escaped}[[:space:]]*=" "$file"; then
        sed -i -E "s|^[[:space:]]*${key_escaped}[[:space:]]*=.*|${key} = ${value_escaped}|" "$file"
    else
        printf '\n%s = %s\n' "$key" "$value" >> "$file"
    fi
}

resolve_module_conf() {
    local dir="$1"
    shift
    local candidate
    local conf_file
    local conf_base

    # 1) Preferred exact filenames first (ordered)
    for candidate in "$@"; do
        if [ -f "$dir/$candidate" ]; then
            printf '%s\n' "$dir/$candidate"
            return 0
        fi
    done

    # 2) Fallback: case-insensitive match for robustness
    shopt -s nullglob
    for conf_file in "$dir"/*.conf; do
        conf_base="$(basename "$conf_file")"
        for candidate in "$@"; do
            if [ "${conf_base,,}" = "${candidate,,}" ]; then
                shopt -u nullglob
                printf '%s\n' "$conf_file"
                return 0
            fi
        done
    done
    shopt -u nullglob

    return 1
}

resolve_ahbot_guids() {
    local mysql_host="${DB_HOST:-127.0.0.1}"
    local mysql_port="${DB_PORT:-3306}"
    local q_account1
    local q_fallback
    local guids

    q_account1="SELECT GROUP_CONCAT(guid ORDER BY guid SEPARATOR ',') FROM (SELECT guid FROM acore_characters.characters WHERE account = 1 ORDER BY guid LIMIT 3) t;"
    q_fallback="SELECT GROUP_CONCAT(guid ORDER BY guid SEPARATOR ',') FROM (SELECT guid FROM acore_characters.characters ORDER BY guid LIMIT 3) t;"

    if ! command -v mysql >/dev/null 2>&1; then
        echo "[WARN] mysql client not found; AuctionHouseBot.GUIDs not changed"
        return 1
    fi

    if guids=$(MYSQL_PWD="$DB_PASS" mysql -N -s -h "$mysql_host" -P "$mysql_port" -u "$DB_USER" -e "$q_account1" 2>/dev/null); then
        :
    else
        echo "[WARN] GUID query failed for account=1; using global AHBot fallback"
        if guids=$(MYSQL_PWD="$DB_PASS" mysql -N -s -h "$mysql_host" -P "$mysql_port" -u "$DB_USER" -e "$q_fallback" 2>/dev/null); then
            :
        else
            echo "[WARN] AHBot fallback GUID query failed; AuctionHouseBot.GUIDs not changed"
            return 1
        fi
    fi

    if [ -n "${guids:-}" ] && [ "$guids" != "NULL" ]; then
        printf '%s\n' "$guids"
        return 0
    fi

    if guids=$(MYSQL_PWD="$DB_PASS" mysql -N -s -h "$mysql_host" -P "$mysql_port" -u "$DB_USER" -e "$q_fallback" 2>/dev/null); then
        if [ -n "${guids:-}" ] && [ "$guids" != "NULL" ]; then
            printf '%s\n' "$guids"
            return 0
        fi
    else
        echo "[WARN] AHBot fallback GUID query failed; AuctionHouseBot.GUIDs not changed"
        return 1
    fi

    echo "[WARN] No character found; AuctionHouseBot.GUIDs not changed"
    return 1
}

echo "========================================"
echo "Downloading client data"
echo "========================================"

cd "$AC_BIN_DIR"

# Cache directory on the host
HOST_DATA_DIR="/vagrant/data"
mkdir -p "$HOST_DATA_DIR"

if [ ! -f "data-version" ]; then
  if [ ! -f "$HOST_DATA_DIR/data.zip" ]; then
    echo "Downloading data files to the host cache..."
    if ! timeout 7200 wget -q --show-progress -O "$HOST_DATA_DIR/data.zip" https://github.com/wowgaming/client-data/releases/download/v19/data.zip; then
      echo "[ERROR] Download failed"
      exit 1
    fi
    echo "[OK] Download succeeded."
  else
    echo "[OK] data.zip found in host cache."
  fi

  echo "Extracting data..."
  if ! unzip -qo "$HOST_DATA_DIR/data.zip" -d .; then
    echo "[ERROR] Extraction failed"
    exit 1
  fi
  touch data-version
  echo "[OK] Data files extracted."
else
  echo "[OK] Data files already present in the VM."
fi

echo "========================================"
echo "Configuring .conf files"
echo "========================================"

cd "$AC_CONF_DIR"

[ ! -f "authserver.conf" ] && cp authserver.conf.dist authserver.conf && echo "[OK] authserver.conf created"
[ ! -f "worldserver.conf" ] && cp worldserver.conf.dist worldserver.conf && echo "[OK] worldserver.conf created"
[ ! -f "dbimport.conf" ] && cp dbimport.conf.dist dbimport.conf && echo "[OK] dbimport.conf created"

# Explicit DB credential sync from .env (with fallback if the key is missing)
ensure_conf_kv authserver.conf "LoginDatabaseInfo" "\"127.0.0.1;3306;$DB_USER;$DB_PASS;acore_auth\""
ensure_conf_kv worldserver.conf "LoginDatabaseInfo" "\"127.0.0.1;3306;$DB_USER;$DB_PASS;acore_auth\""
ensure_conf_kv worldserver.conf "WorldDatabaseInfo" "\"127.0.0.1;3306;$DB_USER;$DB_PASS;acore_world\""
ensure_conf_kv worldserver.conf "CharacterDatabaseInfo" "\"127.0.0.1;3306;$DB_USER;$DB_PASS;acore_characters\""
ensure_conf_kv dbimport.conf "LoginDatabaseInfo" "\"127.0.0.1;3306;$DB_USER;$DB_PASS;acore_auth\""
ensure_conf_kv dbimport.conf "WorldDatabaseInfo" "\"127.0.0.1;3306;$DB_USER;$DB_PASS;acore_world\""
ensure_conf_kv dbimport.conf "CharacterDatabaseInfo" "\"127.0.0.1;3306;$DB_USER;$DB_PASS;acore_characters\""
ensure_conf_kv dbimport.conf "Updates.ExceptionShutdownDelay" "10000"
ensure_conf_kv worldserver.conf "EnablePlayerSettings" "1"
ensure_conf_kv worldserver.conf "Rate.Corpse.Decay.Looted" "0.01"
ensure_conf_kv worldserver.conf "Quests.IgnoreAutoAccept" "1"
ensure_conf_kv worldserver.conf "PreloadAllNonInstancedMapGrids" "0"
ensure_conf_kv worldserver.conf "SetAllCreaturesWithWaypointMovementActive" "0"
ensure_conf_kv worldserver.conf "DontCacheRandomMovementPaths" "0"
ensure_conf_kv worldserver.conf "MapUpdate.Threads" "4"
ensure_conf_kv worldserver.conf "MapUpdateInterval" "50"
ensure_conf_kv worldserver.conf "MinWorldUpdateTime" "10"
ensure_conf_kv worldserver.conf "Console.Enable" "0"
ensure_conf_kv worldserver.conf "SOAP.Enabled" "1"
ensure_conf_kv worldserver.conf "SOAP.IP" "\"127.0.0.1\""
ensure_conf_kv worldserver.conf "SOAP.Port" "${SOAP_PORT:-7878}"
ensure_conf_kv worldserver.conf "SOAP.User" "\"${SOAP_USER:-admin}\""
ensure_conf_kv worldserver.conf "SOAP.Pass" "\"${SOAP_PASS:-admin}\""
ensure_conf_kv worldserver.conf "Network.OutUBuff" "16384"
ensure_conf_kv worldserver.conf "PlayerSaveInterval" "300000"
ensure_conf_kv worldserver.conf "PlayerLimit" "0"
ensure_conf_kv worldserver.conf "LeaveGroupOnLogout.Enabled" "1"

# Module activation
echo "Enabling module configurations..."
cd modules/
shopt -s nullglob
for f in *.dist; do
    target="${f%.dist}"
    if [ ! -f "$target" ]; then
        cp "$f" "$target"
        echo "[OK] Module enabled: $target"
    fi
done
shopt -u nullglob

# DB sync for mod-playerbots (takes precedence over worldserver.conf)
if [ -f "playerbots.conf" ]; then
    ensure_conf_kv playerbots.conf "PlayerbotsDatabaseInfo" "\"127.0.0.1;3306;$DB_USER;$DB_PASS;acore_playerbots\""
    ensure_conf_kv playerbots.conf "AiPlayerbot.Enabled" "1"
    ensure_conf_kv playerbots.conf "AiPlayerbot.DeleteRandomBotAccounts" "0"
    ensure_conf_kv playerbots.conf "AiPlayerbot.RandomBotAccountPrefix" "\"rndbot\""
    ensure_conf_kv playerbots.conf "AiPlayerbot.MinRandomBots" "300"
    ensure_conf_kv playerbots.conf "AiPlayerbot.MaxRandomBots" "500"
    ensure_conf_kv playerbots.conf "AiPlayerbot.RandomBotMinLevel" "1"
    ensure_conf_kv playerbots.conf "AiPlayerbot.RandomBotMaxLevel" "80"
    ensure_conf_kv playerbots.conf "AiPlayerbot.AutoTeleportForLevel" "1"
    ensure_conf_kv playerbots.conf "AiPlayerbot.RandomBotMaps" "\"0,1,530,571\""
    ensure_conf_kv playerbots.conf "AiPlayerbot.ProbTeleToBankers" "0.25"
    ensure_conf_kv playerbots.conf "AiPlayerbot.RandomBotMaxLevelChance" "0.01"
    ensure_conf_kv playerbots.conf "AiPlayerbot.RandomBotFixedLevel" "0"
    ensure_conf_kv playerbots.conf "AiPlayerbot.DisableRandomLevels" "0"
    ensure_conf_kv playerbots.conf "AiPlayerbot.RandombotStartingLevel" "5"
    ensure_conf_kv playerbots.conf "AiPlayerbot.SyncLevelWithPlayers" "0"
    ensure_conf_kv playerbots.conf "AiPlayerbot.SyncQuestWithPlayer" "1"
    ensure_conf_kv playerbots.conf "AiPlayerbot.AutoDoQuests" "1"
    ensure_conf_kv playerbots.conf "AiPlayerbot.AutoGearQualityLimit" "4"
    ensure_conf_kv playerbots.conf "AiPlayerbot.AutoGearScoreLimit" "0"
    ensure_conf_kv playerbots.conf "AiPlayerbot.AutoGearCommand" "1"
    ensure_conf_kv playerbots.conf "AiPlayerbot.MaintenanceCommand" "1"
    ensure_conf_kv playerbots.conf "AiPlayerbot.AllowPlayerBots" "1"
    ensure_conf_kv playerbots.conf "AiPlayerbot.AllowGuildBots" "1"
    ensure_conf_kv playerbots.conf "AiPlayerbot.EnableBroadcasts" "0"
    ensure_conf_kv playerbots.conf "AiPlayerbot.RandomBotTalk" "0"
    ensure_conf_kv playerbots.conf "AiPlayerbot.RandomBotEmote" "0"
    ensure_conf_kv playerbots.conf "AiPlayerbot.RandomBotSuggestDungeons" "0"
    ensure_conf_kv playerbots.conf "AiPlayerbot.EnableGreet" "0"
    ensure_conf_kv playerbots.conf "AiPlayerbot.ToxicLinksRepliesChance" "0"
    ensure_conf_kv playerbots.conf "AiPlayerbot.ThunderfuryRepliesChance" "0"
    ensure_conf_kv playerbots.conf "AiPlayerbot.GuildRepliesRate" "0"
    ensure_conf_kv playerbots.conf "AiPlayerbot.GuildFeedback" "0"
    ensure_conf_kv playerbots.conf "AiPlayerbot.RandomBotSayWithoutMaster" "0"
    ensure_conf_kv playerbots.conf "AiPlayerbot.RandomBotUpdateInterval" "20"
    ensure_conf_kv playerbots.conf "AiPlayerbot.RandomBotCountChangeMinInterval" "1800"
    ensure_conf_kv playerbots.conf "AiPlayerbot.RandomBotCountChangeMaxInterval" "7200"
    ensure_conf_kv playerbots.conf "AiPlayerbot.MinRandomBotInWorldTime" "3600"
    ensure_conf_kv playerbots.conf "AiPlayerbot.MaxRandomBotInWorldTime" "86400"
    ensure_conf_kv playerbots.conf "AiPlayerbot.MinRandomBotRandomizeTime" "7200"
    ensure_conf_kv playerbots.conf "AiPlayerbot.MaxRandomBotRandomizeTime" "1209600"
    ensure_conf_kv playerbots.conf "AiPlayerbot.RandomBotsPerInterval" "60"
    ensure_conf_kv playerbots.conf "AiPlayerbot.MinRandomBotReviveTime" "60"
    ensure_conf_kv playerbots.conf "AiPlayerbot.MaxRandomBotReviveTime" "300"
    ensure_conf_kv playerbots.conf "AiPlayerbot.MinRandomBotTeleportInterval" "3600"
    ensure_conf_kv playerbots.conf "AiPlayerbot.MaxRandomBotTeleportInterval" "18000"
    ensure_conf_kv playerbots.conf "AiPlayerbot.RandomBotInWorldWithRotationDisabled" "31104000"
    ensure_conf_kv playerbots.conf "AiPlayerbot.FarDistance" "20.0"
    ensure_conf_kv playerbots.conf "AiPlayerbot.SightDistance" "75.0"
    ensure_conf_kv playerbots.conf "AiPlayerbot.SpellDistance" "28.5"
    ensure_conf_kv playerbots.conf "AiPlayerbot.ShootDistance" "26.0"
    ensure_conf_kv playerbots.conf "AiPlayerbot.ReactDistance" "150.0"
    ensure_conf_kv playerbots.conf "AiPlayerbot.GrindDistance" "75.0"
    ensure_conf_kv playerbots.conf "AiPlayerbot.HealDistance" "38.5"
    ensure_conf_kv playerbots.conf "AiPlayerbot.LootDistance" "25.0"
    ensure_conf_kv playerbots.conf "AiPlayerbot.FleeDistance" "8.0"
    ensure_conf_kv playerbots.conf "AiPlayerbot.TooCloseDistance" "5.0"
    ensure_conf_kv playerbots.conf "AiPlayerbot.MeleeDistance" "1.5"
    ensure_conf_kv playerbots.conf "AiPlayerbot.FollowDistance" "1.5"
    ensure_conf_kv playerbots.conf "AiPlayerbot.WhisperDistance" "6000.0"
    ensure_conf_kv playerbots.conf "AiPlayerbot.ContactDistance" "0.5"
    ensure_conf_kv playerbots.conf "AiPlayerbot.AoeRadius" "10"
    ensure_conf_kv playerbots.conf "AiPlayerbot.RpgDistance" "200"
    ensure_conf_kv playerbots.conf "AiPlayerbot.AggroDistance" "22"
    ensure_conf_kv playerbots.conf "AiPlayerbot.BotActiveAlone" "10"
    ensure_conf_kv playerbots.conf "AiPlayerbot.botActiveAloneSmartScale" "1"
    ensure_conf_kv playerbots.conf "AiPlayerbot.botActiveAloneSmartScaleWhenMinLevel" "1"
    ensure_conf_kv playerbots.conf "AiPlayerbot.botActiveAloneSmartScaleWhenMaxLevel" "80"
    ensure_conf_kv playerbots.conf "PlayerbotsDatabase.WorkerThreads" "2"
    ensure_conf_kv playerbots.conf "PlayerbotsDatabase.SynchThreads" "2"
fi

# Bot Level Brackets settings (if module is present)
if [ -f "mod_player_bot_level_brackets.conf" ]; then
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Enabled" "1"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.FullDebugMode" "0"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.LiteDebugMode" "0"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.CheckFrequency" "300"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.CheckFlaggedFrequency" "15"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.FlaggedProcessLimit" "5"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.NumRanges" "9"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Dynamic.UseDynamicDistribution" "0"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Dynamic.RealPlayerWeight" "1.0"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Dynamic.SyncFactions" "0"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.IgnoreFriendListed" "1"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.IgnoreGuildBotsWithRealPlayers" "1"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.GuildTrackerUpdateFrequency" "600"

    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range1.Lower" "1"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range1.Upper" "9"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range1.Pct" "8"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range2.Lower" "10"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range2.Upper" "19"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range2.Pct" "10"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range3.Lower" "20"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range3.Upper" "29"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range3.Pct" "12"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range4.Lower" "30"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range4.Upper" "39"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range4.Pct" "14"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range5.Lower" "40"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range5.Upper" "49"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range5.Pct" "14"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range6.Lower" "50"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range6.Upper" "59"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range6.Pct" "14"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range7.Lower" "60"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range7.Upper" "69"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range7.Pct" "12"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range8.Lower" "70"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range8.Upper" "79"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range8.Pct" "10"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range9.Lower" "80"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range9.Upper" "80"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Alliance.Range9.Pct" "6"

    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range1.Lower" "1"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range1.Upper" "9"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range1.Pct" "8"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range2.Lower" "10"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range2.Upper" "19"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range2.Pct" "10"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range3.Lower" "20"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range3.Upper" "29"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range3.Pct" "12"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range4.Lower" "30"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range4.Upper" "39"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range4.Pct" "14"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range5.Lower" "40"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range5.Upper" "49"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range5.Pct" "14"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range6.Lower" "50"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range6.Upper" "59"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range6.Pct" "14"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range7.Lower" "60"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range7.Upper" "69"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range7.Pct" "12"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range8.Lower" "70"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range8.Upper" "79"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range8.Pct" "10"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range9.Lower" "80"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range9.Upper" "80"
    ensure_conf_kv mod_player_bot_level_brackets.conf "BotLevelBrackets.Horde.Range9.Pct" "6"
fi

# Transmogrification settings (if module is present)
if [ -f "transmog.conf" ]; then
    # Use ensure_conf_kv (idempotent) to avoid duplicate keys
    ensure_conf_kv transmog.conf "Transmogrification.UseVendorInterface" "1"
    ensure_conf_kv transmog.conf "Transmogrification.ScaledCostModifier" "0"
    ensure_conf_kv transmog.conf "Transmogrification.AllowPoor" "1"
    ensure_conf_kv transmog.conf "Transmogrification.AllowCommon" "1"
    ensure_conf_kv transmog.conf "Transmogrification.AllowUncommon" "1"
    ensure_conf_kv transmog.conf "Transmogrification.AllowRare" "1"
    ensure_conf_kv transmog.conf "Transmogrification.AllowEpic" "1"
    ensure_conf_kv transmog.conf "Transmogrification.AllowLegendary" "1"
    ensure_conf_kv transmog.conf "Transmogrification.AllowArtifact" "1"
    ensure_conf_kv transmog.conf "Transmogrification.AllowHeirloom" "1"
    ensure_conf_kv transmog.conf "Transmogrification.AllowTradeable" "1"
    ensure_conf_kv transmog.conf "Transmogrification.AllowMixedArmorTypes" "1"
    ensure_conf_kv transmog.conf "Transmogrification.AllowLowerTiers" "1"
    ensure_conf_kv transmog.conf "Transmogrification.AllowMixedOffhandArmorTypes" "1"
    ensure_conf_kv transmog.conf "Transmogrification.AllowMixedWeaponTypes" "2"
    ensure_conf_kv transmog.conf "Transmogrification.AllowMixedWeaponHandedness" "1"
    ensure_conf_kv transmog.conf "Transmogrification.AllowFishingPoles" "0"
    ensure_conf_kv transmog.conf "Transmogrification.SetCostModifier" "0"
fi

# Reagent Bank Account settings (if module is present)
if [ -f "mod_reagent_bank_account.conf" ]; then
    ensure_conf_kv mod_reagent_bank_account.conf "ReagentBankAccount.Enable" "1"
fi

# Daily Reset settings (if module is present)
DAILY_RESET_MODULE_CONF="$(resolve_module_conf "$AC_CONF_DIR/modules" "mod_daily_reset.conf" "daily-reset.conf" "daily_reset.conf" || true)"
if [ -n "${DAILY_RESET_MODULE_CONF:-}" ]; then
    ensure_conf_kv "$DAILY_RESET_MODULE_CONF" "DailyReset.Enable" "1"
    ensure_conf_kv "$DAILY_RESET_MODULE_CONF" "DailyReset.Enabled" "1"
fi

# Fly Anywhere settings (if module is present)
FLY_ANYWHERE_MODULE_CONF="$(resolve_module_conf "$AC_CONF_DIR/modules" "fly-anywhere.conf" "mod_fly_anywhere.conf" || true)"
if [ -n "${FLY_ANYWHERE_MODULE_CONF:-}" ]; then
    ensure_conf_kv "$FLY_ANYWHERE_MODULE_CONF" "FlyAnywhere.Enabled" "true"
fi

# Robust module configuration file resolution (case may vary)
AHBOT_MODULE_CONF="$(resolve_module_conf "$AC_CONF_DIR/modules" "mod_ahbot.conf" "AuctionHouseBot.conf" "ahbot.conf" || true)"
AUTOBALANCE_MODULE_CONF="$(resolve_module_conf "$AC_CONF_DIR/modules" "AutoBalance.conf" "mod_autobalance.conf" "autobalance.conf" || true)"

cd ..

echo "========================================"
echo "Applying patches"
echo "========================================"

REAGENT_BANK_NPC_SQL="$AC_CODE_DIR/modules/mod-reagent-bank-account/data/sql/db-world/base/mod_reagent_bank_account_NPC.sql"
if [ -f "$REAGENT_BANK_NPC_SQL" ]; then
    if grep -q "mechanic_immune_mask" "$REAGENT_BANK_NPC_SQL"; then
        sed -i 's/mechanic_immune_mask/CreatureImmunitiesId/g' "$REAGENT_BANK_NPC_SQL"
        echo "[OK] mod-reagent-bank-account SQL compatibility applied (mechanic_immune_mask -> CreatureImmunitiesId)"
    else
        echo "[OK] mod-reagent-bank-account SQL compatibility already up to date"
    fi
else
    echo "[WARN] mod-reagent-bank-account SQL not found: $REAGENT_BANK_NPC_SQL"
fi

ensure_conf_kv worldserver.conf "PlayerbotsDatabaseInfo" "\"127.0.0.1;3306;$DB_USER;$DB_PASS;acore_playerbots\""

ensure_conf_kv worldserver.conf "MailDeliveryDelay" "0"
ensure_conf_kv worldserver.conf "AllowTwoSide.Interaction.Auction" "1"
ensure_conf_kv worldserver.conf "Rate.XP.Kill" "2"
ensure_conf_kv worldserver.conf "Rate.XP.Quest" "2"
ensure_conf_kv worldserver.conf "Rate.Drop.Money" "2"
ensure_conf_kv worldserver.conf "SkillGain.Crafting" "2"
ensure_conf_kv worldserver.conf "SkillGain.Gathering" "2"
ensure_conf_kv worldserver.conf "SkillGain.Weapon" "5"
ensure_conf_kv worldserver.conf "SkillGain.Defense" "5"
echo "[OK] Rates patch applied"

if [ -n "${AHBOT_MODULE_CONF:-}" ]; then
ensure_conf_kv "$AHBOT_MODULE_CONF" "AuctionHouseBot.DEBUG" "false"
ensure_conf_kv "$AHBOT_MODULE_CONF" "AuctionHouseBot.DEBUG_FILTERS" "false"
ensure_conf_kv "$AHBOT_MODULE_CONF" "AuctionHouseBot.AuctionHouseManagerCyclesBetweenBuyOrSell" "1"
ensure_conf_kv "$AHBOT_MODULE_CONF" "AuctionHouseBot.EnableSeller" "true"
ensure_conf_kv "$AHBOT_MODULE_CONF" "AuctionHouseBot.Buyer.Enabled" "false"
if AHBOT_GUIDS="$(resolve_ahbot_guids)"; then
    ensure_conf_kv "$AHBOT_MODULE_CONF" "AuctionHouseBot.GUIDs" "$AHBOT_GUIDS"
    echo "[OK] AuctionHouseBot.GUIDs detected: $AHBOT_GUIDS"
else
    echo "[WARN] Unable to determine AuctionHouseBot.GUIDs automatically; existing value kept"
fi
ensure_conf_kv "$AHBOT_MODULE_CONF" "AuctionHouseBot.ItemsPerCycle" "575"
ensure_conf_kv "$AHBOT_MODULE_CONF" "AuctionHouseBot.Alliance.MinItems" "15000"
ensure_conf_kv "$AHBOT_MODULE_CONF" "AuctionHouseBot.Alliance.MaxItems" "35000"
ensure_conf_kv "$AHBOT_MODULE_CONF" "AuctionHouseBot.Horde.MinItems" "15000"
ensure_conf_kv "$AHBOT_MODULE_CONF" "AuctionHouseBot.Horde.MaxItems" "35000"
ensure_conf_kv "$AHBOT_MODULE_CONF" "AuctionHouseBot.Neutral.MinItems" "15000"
ensure_conf_kv "$AHBOT_MODULE_CONF" "AuctionHouseBot.Neutral.MaxItems" "35000"
echo "[OK] AHBot patch applied (${AHBOT_MODULE_CONF})"
else
echo "[WARN] AHBot config file not found in $AC_CONF_DIR/modules (candidates: mod_ahbot.conf, AuctionHouseBot.conf, ahbot.conf)"
fi

if [ -n "${AUTOBALANCE_MODULE_CONF:-}" ]; then
ensure_conf_kv "$AUTOBALANCE_MODULE_CONF" "AutoBalance.Enable" "1"
ensure_conf_kv "$AUTOBALANCE_MODULE_CONF" "AutoBalance.PlayerBots.CountAsPlayers" "1"
ensure_conf_kv "$AUTOBALANCE_MODULE_CONF" "AutoBalance.MinPlayers" "1"
ensure_conf_kv "$AUTOBALANCE_MODULE_CONF" "AutoBalance.5.Man.Instance" "1"
ensure_conf_kv "$AUTOBALANCE_MODULE_CONF" "AutoBalance.10.Man.Instance" "1"
ensure_conf_kv "$AUTOBALANCE_MODULE_CONF" "AutoBalance.25.Man.Instance" "1"
ensure_conf_kv "$AUTOBALANCE_MODULE_CONF" "AutoBalance.40.Man.Instance" "1"
ensure_conf_kv "$AUTOBALANCE_MODULE_CONF" "AutoBalance.InflectionPoint" "0.5"
ensure_conf_kv "$AUTOBALANCE_MODULE_CONF" "AutoBalance.BossModifier.Health" "1.0"
ensure_conf_kv "$AUTOBALANCE_MODULE_CONF" "AutoBalance.BossModifier.Damage" "0.8"
echo "[OK] AutoBalance patch applied (${AUTOBALANCE_MODULE_CONF})"
else
echo "[WARN] AutoBalance config file not found in $AC_CONF_DIR/modules (candidates: AutoBalance.conf, mod_autobalance.conf, autobalance.conf)"
fi

# Permission repair
sudo chown -R vagrant:vagrant /home/vagrant/azerothcore
chmod 644 *.conf 2>/dev/null || true
chmod 644 modules/*.conf 2>/dev/null || true
echo "[OK] Permissions and configuration complete"
