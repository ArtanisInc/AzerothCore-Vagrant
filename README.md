# AzerothCore Vagrant (WoW 3.3.5a)

Local AzerothCore environment provisioned with Vagrant/VirtualBox for AzerothCore Playerbot, modules, MySQL, systemd services, backups, and diagnostics.

---

## 1) Requirements

- Vagrant
- VirtualBox
- ~40 GB free space for source, build artifacts, databases, and logs
- A WoW 3.3.5a client configured with the generated `realmlist`

---

## 2) First setup

```powershell
copy .env.example .env
vagrant up
```

The first provisioning run builds AzerothCore from source and can take a long time.

After provisioning:

```bash
vagrant ssh
source ~/.bash_aliases
acore-status
acore-health
acore-diagnose
```

If `DB_PASS` is empty in `.env`, provisioning generates one and writes it back to `.env`. Keep that file private.

---

## 3) `.env` configuration

### VM and database

```env
VM_RAM=8192
VM_CPUS=4

DB_USER=acore
DB_PASS=
MYSQL_INNODB_BUFFER_POOL_SIZE=
MYSQL_INNODB_BUFFER_POOL_INSTANCES=
MYSQL_INNODB_LOG_FILE_SIZE_MB=
DB_BACKUP_DIR=/home/vagrant/backups
DB_BACKUP_RETENTION=7
```

Notes:

- If `DB_PASS` is empty or `acore`, provisioning generates a new password.
- If `MYSQL_INNODB_BUFFER_POOL_SIZE` is empty, MySQL uses an adaptive value based on `VM_RAM`.
- `DB_BACKUP_RETENTION` keeps the last N compressed backups per database; `0` disables rotation.

### AzerothCore source

```env
ACORE_REPO=https://github.com/mod-playerbots/azerothcore-wotlk.git
ACORE_BRANCH=Playerbot
ACORE_REF=
```

`ACORE_REF` can pin a specific branch, tag, or commit. If empty, `ACORE_BRANCH` is used.

### Module refs

```env
MOD_PLAYERBOTS_REF=
MOD_AH_BOT_PLUS_REF=
MOD_AUTOBALANCE_REF=
MOD_AOE_LOOT_REF=
MOD_LEARN_SPELLS_REF=
MOD_SOLO_LFG_REF=
MOD_CHALLENGE_MODES_REF=
MOD_PLAYER_BOT_LEVEL_BRACKETS_REF=
MOD_JUNK_TO_GOLD_REF=
MOD_RARE_DROPS_REF=fix
MOD_TRANSMOG_REF=
MOD_REAGENT_BANK_ACCOUNT_REF=
MOD_DAILY_RESET_REF=
MOD_FLY_ANYWHERE_REF=
MOD_MOUNT_SCALING_REF=
MOD_PORTALS_IN_ALL_CAPITALS_REF=
```

Each `MOD_*_REF` can pin that module to a branch, tag, or commit. Empty values use the module repository default branch, except where a project default is provided.

### Realm and admin/SOAP

```env
EXTERNAL_IP=127.0.0.1

SOAP_USER=admin
SOAP_PASS=admin
SOAP_PORT=7878
```

`EXTERNAL_IP` is written to `acore_auth.realmlist.address`. Use your LAN/public IP.

### AHBot account

```env
AHBOT_ACCOUNT_NAME=ahbot
AHBOT_ACCOUNT_PASS=ahbot123!
```

Provisioning creates or updates the AHBot account. It does **not** create the AHBot character directly in SQL.

---

## 4) Included modules

| Module                          | Purpose                                                                                                                                                                                             |
| ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `mod-playerbots`                | Adds AI-controlled player bots and the playerbots database.                                                                                                                                         |
| `mod-ah-bot-plus`               | Populates and manages auction house activity through configured character GUIDs.                                                                                                                    |
| `mod-autobalance`               | Scales dungeon and group content difficulty for smaller groups or solo play.                                                                                                                        |
| `mod-aoe-loot`                  | Adds area loot convenience.                                                                                                                                                                         |
| `mod-learn-spells`              | Automatically teaches class spells while leveling.                                                                                                                                                  |
| `mod-solo-lfg`                  | Makes Looking For Group flows more suitable for solo/small-server play.                                                                                                                             |
| `mod-challenge-modes`           | Adds challenge-mode gameplay support.                                                                                                                                                               |
| `mod-player-bot-level-brackets` | Controls playerbot level distribution by brackets.                                                                                                                                                  |
| `mod-junk-to-gold`              | Converts low-value junk handling into a gold convenience feature.                                                                                                                                   |
| `mod-rare-drops`                | Adds custom rare-drop behavior from the configured fork/ref.                                                                                                                                        |
| `mod-transmog`                  | Adds transmogrification support.                                                                                                                                                                    |
| `mod-reagent-bank-account`      | Adds reagent-bank style storage support.                                                                                                                                                            |
| `mod-daily-reset`               | Adds daily reset utilities.                                                                                                                                                                         |
| `mod-fly-anywhere`              | Allows flying in more zones than stock WotLK rules.                                                                                                                                                 |
| `mod-mount-scaling`             | Adds progressive mount speed scaling by level. Its SQL lowers Apprentice Riding and apprentice ground mount requirements to level 1. Clear the WoW client `Cache` folder after this SQL is applied. |
| `portals-in-all-capitals`       | Adds portal access in all capital cities.                                                                                                                                                           |

---

## 5) AHBot workflow

AHBot needs real character GUIDs. The safe workflow is two-step: provisioning creates the account first; you create the character through the WoW client afterwards.

### 5.1 First provisioning

Keep these values in `.env` before `vagrant up`:

```env
AHBOT_ACCOUNT_NAME=ahbot
AHBOT_ACCOUNT_PASS=ahbot123!
```

Provisioning will create/update the account `ahbot`. Until a dedicated AHBot character exists, the AHBot config may use fallback character GUIDs so the module can still run.

### 5.2 Create the AHBot character

1. Start the server.
2. Open the WoW client.
3. Log in with `ahbot / ahbot123!`.
4. Create a dedicated AHBot character, for example `Vendor`.

### 5.3 Get the character GUID

From host PowerShell, use your actual `DB_PASS` from `.env`:

```powershell
vagrant ssh -c 'MYSQL_PWD="your-db-password" mysql -u acore -h 127.0.0.1 acore_characters -e "SELECT guid, name, account FROM characters WHERE name=\"Vendor\";"'
```

Or from inside the VM:

```bash
source /vagrant/provision/scripts/00-env.sh >/dev/null
MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 acore_characters \
  -e "SELECT guid, name, account FROM characters WHERE name=\"$CHARACTER_NAME\";"
```

### 5.4 Apply the GUID to AHBot

Inside the VM:

```bash
source ~/.bash_aliases
acore-setup-ahbot <ahbot_character_guid>
sudo systemctl restart acore-world
```

`acore-setup-ahbot` updates `AuctionHouseBot.GUIDs` in the AHBot module config under:

```text
/home/vagrant/azerothcore/env/dist/etc/modules/
```

---

## 6) Runtime architecture

- Supervisor: **systemd**
- Services:
  - `acore-auth` → `authserver`
  - `acore-world` → `worldserver`
- Normal runtime does not use `screen`.

---

## 7) Acore commands (aliases)

Aliases are generated by `provision/scripts/06-services.sh` in `/home/vagrant/.bash_aliases`.

Reload aliases after reprovisioning:

```bash
source ~/.bash_aliases
```

> The aliases below run inside the VM Bash shell (`vagrant ssh`), not directly in host PowerShell.

### 7.1 Service management

| Alias           | Executes                                  | Arguments               | Example          |
| --------------- | ----------------------------------------- | ----------------------- | ---------------- |
| `acore-start`   | `./start-servers.sh`                      | none                    | `acore-start`    |
| `acore-stop`    | `./stop-servers.sh`                       | none                    | `acore-stop`     |
| `acore-restart` | `./stop-servers.sh && ./start-servers.sh` | none                    | `acore-restart`  |
| `acore-status`  | `./monitor-servers.sh`                    | none                    | `acore-status`   |
| `acore-watch`   | `./watch-services.sh`                     | `[interval_seconds>=5]` | `acore-watch 10` |

### 7.2 Health, logs, metrics

| Alias            | Executes                                    | Arguments | Example          |
| ---------------- | ------------------------------------------- | --------- | ---------------- |
| `acore-health`   | `./healthcheck.sh`                          | none      | `acore-health`   |
| `acore-metrics`  | `./metrics-snapshot.sh`                     | none      | `acore-metrics`  |
| `acore-diagnose` | `./diagnose-server.sh`                      | none      | `acore-diagnose` |
| `acore-console`  | `journalctl -u acore-world -f`              | none      | `acore-console`  |
| `acore-auth`     | `journalctl -u acore-auth -f`               | none      | `acore-auth`     |
| `acore-log`      | `tail -f .../Server.log`                    | none      | `acore-log`      |
| `acore-errors`   | `grep "ERROR" .../Server.log \| tail -n 20` | none      | `acore-errors`   |

### 7.3 Admin, accounts, gameplay

| Alias                  | Executes                   | Arguments                        | Example                                          |
| ---------------------- | -------------------------- | -------------------------------- | ------------------------------------------------ |
| `acore-create-account` | `./create-account.sh`      | `<username> <password>`          | `acore-create-account admin admin`               |
| `acore-set-gm`         | `./set-gm.sh`              | `<username> <gmlevel> [realmId]` | `acore-set-gm admin 3 -1`                        |
| `acore-world-console`  | `./worldserver-console.sh` | `[suggested command]`            | `acore-world-console "account create test test"` |
| `acore-bots-help`      | `./playerbots-help.sh`     | none                             | `acore-bots-help`                                |
| `acore-setup-ahbot`    | `./setup-ahbot.sh`         | `[guid[,guid...]]`               | `acore-setup-ahbot 123`                          |

### 7.4 DB, config, maintenance

| Alias              | Executes                                                            | Arguments | Example            |
| ------------------ | ------------------------------------------------------------------- | --------- | ------------------ |
| `acore-db`         | `MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 acore_world` | none      | `acore-db`         |
| `acore-conf`       | `nano .../worldserver.conf`                                         | none      | `acore-conf`       |
| `acore-modules`    | `cd .../etc/modules && ls -l`                                       | none      | `acore-modules`    |
| `acore-clean-logs` | `./clean-logs.sh`                                                   | none      | `acore-clean-logs` |
| `acore-backup`     | `./backup-db.sh`                                                    | none      | `acore-backup`     |
| `acore-update`     | `./update-core.sh`                                                  | none      | `acore-update`     |

`acore-backup` saves `acore_auth`, `acore_characters`, `acore_world`, and `acore_playerbots` as `.sql.gz`, then applies the retention configured by `DB_BACKUP_RETENTION`.

---

## 8) Useful database checks

### Realmlist

```bash
source /vagrant/provision/scripts/00-env.sh >/dev/null
MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 \
  -e "SELECT id,name,address,localAddress,port FROM acore_auth.realmlist;"
```

### Characters

```bash
source /vagrant/provision/scripts/00-env.sh >/dev/null
MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 acore_characters \
  -e "SELECT guid, name, account, race, class, level FROM characters ORDER BY guid LIMIT 20;"
```

### AHBot account and dedicated character

```bash
source /vagrant/provision/scripts/00-env.sh >/dev/null
MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 \
  -e "SELECT id, username FROM acore_auth.account WHERE username=UPPER('$AHBOT_ACCOUNT_NAME'); SELECT guid, name, account FROM acore_characters.characters WHERE account IN (SELECT id FROM acore_auth.account WHERE username=UPPER('$AHBOT_ACCOUNT_NAME'));"
```

---

## 9) Ports

### Inside the VM

- `3724` → authserver
- `8085` → worldserver
- `3306` → MySQL
- `7878` → SOAP on localhost

### From the host

- `3724 -> 3724`
- `8085 -> 8085`

Quick check inside the VM:

```bash
ss -ltn | grep -E ':3724|:8085|:3306|:7878'
```

---

## 10) Troubleshooting

### First diagnostic command

```bash
acore-diagnose
```

`acore-health` remains the short probe, `acore-metrics` produces a minimal JSON snapshot, and `acore-diagnose` aggregates systemd, ports, logs, resources, MySQL, realmlist, core/module versions, database sizes, SOAP, and loaded-module indicators.

### Service status

```bash
systemctl status acore-auth acore-world --no-pager
```

### systemd logs

```bash
journalctl -u acore-world -n 200 --no-pager
journalctl -u acore-auth -n 200 --no-pager
```

### Runtime logs

- `/home/vagrant/azerothcore/env/dist/bin/Auth.log`
- `/home/vagrant/azerothcore/env/dist/bin/Server.log`
- `/home/vagrant/azerothcore/logs/health.log`

### Reset failed services

```bash
sudo systemctl reset-failed acore-world acore-auth
sudo systemctl restart acore-auth acore-world
```

---

## 11) Reset or rebuild

Destroy the VM and rebuild from scratch:

```powershell
vagrant halt
vagrant destroy -f
vagrant up
```

Re-run provisioning on the existing VM:

```powershell
vagrant provision
```
