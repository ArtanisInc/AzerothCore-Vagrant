# AzerothCore Vagrant (WoW 3.3.5a)

Environnement local AzerothCore (core + modules) avec provisioning Vagrant/VirtualBox.

---

## 1) Prérequis

- Vagrant
- VirtualBox
- ~40 Go libres (build + base de données + logs)

---

## 2) Configuration `.env`

Copie `.env.example` vers `.env`, puis ajuste les variables.

### Variables principales

```env
VM_RAM=8192
VM_CPUS=4

DB_USER=acore
DB_PASS=

ACORE_REPO=https://github.com/mod-playerbots/azerothcore-wotlk.git
ACORE_BRANCH=Playerbot
ACORE_REF=

MOD_PLAYERBOTS_REF=
MOD_AH_BOT_PLUS_REF=
MOD_AUTOBALANCE_REF=
MOD_AOE_LOOT_REF=
MOD_LEARN_SPELLS_REF=
MOD_SOLO_LFG_REF=
MOD_CHALLENGE_MODES_REF=
MOD_RARE_DROPS_REF=fix
MOD_PORTALS_IN_ALL_CAPITALS_REF=

EXTERNAL_IP=
```

### Notes

- Si `DB_PASS` est vide (ou `acore`), le provisioning génère un mot de passe et l’écrit dans `.env`.
- `EXTERNAL_IP` est utilisé pour configurer l’adresse IP du realm.

---

## 3) Démarrage rapide

```bash
vagrant up
vagrant ssh
source ~/.bash_aliases
acore-start
acore-health
```

⚠️ Le premier build peut être long. `worldserver` peut prendre plusieurs minutes avant d’ouvrir le port `8085`.

---

## 4) Architecture runtime

- Supervision: **systemd**
- Services:
  - `acore-auth` → `authserver`
  - `acore-world` → `worldserver`
- Le runtime normal n’utilise pas `screen`.

---

## 5) Commandes Acore (aliases)

Les aliases sont générés par `provision/scripts/06-services.sh` dans `/home/vagrant/.bash_aliases`.

Recharge après reprovision:

```bash
source ~/.bash_aliases
```

> Les aliases/commandes ci-dessous s'exécutent **dans la VM Bash** (`vagrant ssh`), pas directement dans PowerShell hôte.

### Convention VM vs PowerShell (copier-coller)

- **VM Bash** : entre dans la VM puis exécute les commandes telles quelles.
- **PowerShell hôte** : passe les commandes Bash via `vagrant ssh -c "..."`.

Exemple équivalent (sélection realmlist):

```bash
# VM Bash
source /vagrant/provision/scripts/00-env.sh >/dev/null
MYSQL_PWD="$DB_PASS" mysql -u"$DB_USER" -h 127.0.0.1 -e "SELECT id,name,address,localAddress,port FROM acore_auth.realmlist;"
```

```powershell
# PowerShell hôte
vagrant ssh -c "source /vagrant/provision/scripts/00-env.sh >/dev/null; MYSQL_PWD=\"`$DB_PASS\" mysql -u\"`$DB_USER\" -h 127.0.0.1 -e \"SELECT id,name,address,localAddress,port FROM acore_auth.realmlist;\""
```

### 5.1 Gestion des services

| Alias           | Exécution                                 | Arguments               | Exemple          |
| --------------- | ----------------------------------------- | ----------------------- | ---------------- |
| `acore-start`   | `./start-servers.sh`                      | aucun                   | `acore-start`    |
| `acore-stop`    | `./stop-servers.sh`                       | aucun                   | `acore-stop`     |
| `acore-restart` | `./stop-servers.sh && ./start-servers.sh` | aucun                   | `acore-restart`  |
| `acore-status`  | `./monitor-servers.sh`                    | aucun                   | `acore-status`   |
| `acore-watch`   | `./watch-services.sh`                     | `[interval_seconds>=5]` | `acore-watch 10` |

### 5.2 Santé, logs, métriques

| Alias           | Exécution                                   | Arguments | Exemple         |
| --------------- | ------------------------------------------- | --------- | --------------- |
| `acore-health`  | `./healthcheck.sh`                          | aucun     | `acore-health`  |
| `acore-metrics` | `./metrics-snapshot.sh`                     | aucun     | `acore-metrics` |
| `acore-console` | `journalctl -u acore-world -f`              | aucun     | `acore-console` |
| `acore-auth`    | `journalctl -u acore-auth -f`               | aucun     | `acore-auth`    |
| `acore-log`     | `tail -f .../Server.log`                    | aucun     | `acore-log`     |
| `acore-errors`  | `grep "ERROR" .../Server.log \| tail -n 20` | aucun     | `acore-errors`  |

### 5.3 Admin, comptes, gameplay

| Alias                  | Exécution                  | Arguments                        | Exemple                                          |
| ---------------------- | -------------------------- | -------------------------------- | ------------------------------------------------ |
| `acore-create-account` | `./create-account.sh`      | `<username> <password>`          | `acore-create-account admin admin`               |
| `acore-set-gm`         | `./set-gm.sh`              | `<username> <gmlevel> [realmId]` | `acore-set-gm admin 3 -1`                        |
| `acore-world-console`  | `./worldserver-console.sh` | `[commande suggérée]`            | `acore-world-console "account create test test"` |
| `acore-bots-help`      | `./playerbots-help.sh`     | aucun                            | `acore-bots-help`                                |
| `acore-setup-ahbot`    | `./setup-ahbot.sh`         | interactif                       | `acore-setup-ahbot`                              |

### 5.4 DB, config, maintenance

| Alias              | Exécution                                                           | Arguments | Exemple            |
| ------------------ | ------------------------------------------------------------------- | --------- | ------------------ |
| `acore-db`         | `MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" -h 127.0.0.1 acore_world` | aucun     | `acore-db`         |
| `acore-conf`       | `nano .../worldserver.conf`                                         | aucun     | `acore-conf`       |
| `acore-modules`    | `cd .../etc/modules && ls -l`                                       | aucun     | `acore-modules`    |
| `acore-clean-logs` | `./clean-logs.sh`                                                   | aucun     | `acore-clean-logs` |
| `acore-backup`     | `./backup-db.sh`                                                    | aucun     | `acore-backup`     |
| `acore-update`     | `./update-core.sh`                                                  | aucun     | `acore-update`     |

---

## 6) Ports

### Dans la VM

- `3724` → authserver
- `8085` → worldserver
- `3306` → mysql

### Depuis l’hôte

- `3724 -> 3724`
- `8085 -> 8085`
- `3307 -> 3306` (forward MySQL)

Vérif rapide:

```bash
ss -ltn | grep -E ':3724|:8085|:3306'
```

---

## 7) Dépannage rapide

### Statut des services

```bash
systemctl status acore-auth acore-world --no-pager
```

### Logs systemd

```bash
journalctl -u acore-world -n 200 --no-pager
journalctl -u acore-auth -n 200 --no-pager
```

### Santé applicative

```bash
# (dans une nouvelle session VM, pense à recharger les aliases)
# source ~/.bash_aliases
acore-health
acore-metrics
```

### Logs runtime

- `/home/vagrant/azerothcore/env/dist/bin/Auth.log`
- `/home/vagrant/azerothcore/env/dist/bin/Server.log`
- `/home/vagrant/azerothcore/logs/health.log`

### Réinitialiser des services en échec

```bash
sudo systemctl reset-failed acore-world acore-auth
sudo systemctl restart acore-auth acore-world
```
