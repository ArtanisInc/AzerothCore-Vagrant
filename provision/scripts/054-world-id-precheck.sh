#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

echo "========================================"
echo "Precheck SQL world IDs (modules)"
echo "========================================"

if ! command -v mysql >/dev/null 2>&1; then
  echo "[ERROR] Client mysql introuvable. Precheck impossible."
  exit 1
fi

DB_HOST_CHECK="${DB_HOST:-127.0.0.1}"
MYSQL_BASE=(env MYSQL_PWD="$DB_PASS" mysql -u"$DB_USER" -h "$DB_HOST_CHECK" --protocol=tcp --batch --skip-column-names)

if ! "${MYSQL_BASE[@]}" -e "SELECT 1" acore_world >/dev/null 2>&1; then
  echo "[ERROR] Impossible de joindre MySQL/acore_world avec les credentials courants."
  exit 1
fi

MODULES_DIR="$AC_CODE_DIR/modules"
if [ ! -d "$MODULES_DIR" ]; then
  echo "[ERROR] Dossier modules introuvable: $MODULES_DIR"
  exit 1
fi

declare -A TABLE_ID_COL=(
  [gameobject]=guid
  [creature]=guid
  [gossip_menu]=entry
  [npc_text]=ID
  [creature_template]=entry
  [gameobject_template]=entry
)

target_modules=(
  "portals-in-all-capitals"
  "mod-rare-drops"
)

declare -a sql_files=()
for mod in "${target_modules[@]}"; do
  mod_dir="$MODULES_DIR/$mod"
  if [ -d "$mod_dir" ]; then
    while IFS= read -r file; do
      sql_files+=("$file")
    done < <(find "$mod_dir" -type f -name '*.sql' 2>/dev/null)
  fi
done

if [ "${#sql_files[@]}" -eq 0 ]; then
  echo "[OK] Aucun SQL cible trouve pour precheck."
  exit 0
fi

tmp_candidates="$(mktemp)"
trap 'rm -f "$tmp_candidates"' EXIT

for file in "${sql_files[@]}"; do
  module_name="$(basename "$(dirname "$file")")"
  case "$file" in
    *"/portals-in-all-capitals/"*) module_name="portals-in-all-capitals" ;;
    *"/mod-rare-drops/"*) module_name="mod-rare-drops" ;;
  esac

  perl -0777 -ne '
    my $sql = $_;
    while ($sql =~ /INSERT\s+INTO\s+`?([a-zA-Z0-9_]+)`?[^;]*?VALUES\s*(.+?);/sig) {
      my ($table, $values) = (lc($1), $2);
      next unless $table =~ /^(gameobject|creature|gossip_menu|npc_text|creature_template|gameobject_template)$/;

      while ($values =~ /\(([^()]*)\)/g) {
        my $row = $1;
        my ($first) = split(/,/, $row, 2);
        next unless defined $first;
        $first =~ s/^\s+|\s+$//g;
        $first =~ s/^`|`$//g;
        $first =~ s/^"|"$//g;
        $first =~ s/^\x27|\x27$//g;
        next unless $first =~ /^-?\d+$/;
        print "$table\t$first\n";
      }
    }
  ' "$file" | while IFS=$'\t' read -r table id; do
    printf '%s\t%s\t%s\t%s\n' "$module_name" "$file" "$table" "$id" >> "$tmp_candidates"
  done
done

if [ ! -s "$tmp_candidates" ]; then
  echo "[OK] Aucun INSERT ID numerique detecte sur tables cibles."
  exit 0
fi

declare -A checked
conflict=0

while IFS=$'\t' read -r module file table id; do
  key="$table:$id"
  if [ -n "${checked[$key]:-}" ]; then
    continue
  fi

  id_col="${TABLE_ID_COL[$table]:-}"
  if [ -z "$id_col" ]; then
    continue
  fi

  exists="$("${MYSQL_BASE[@]}" -e "SELECT 1 FROM \`${table}\` WHERE \`${id_col}\` = ${id} LIMIT 1" acore_world 2>/dev/null || true)"
  checked[$key]=1

  if [ "$exists" = "1" ]; then
    echo "[ERROR] Conflit ID potentiel detecte: module=$module file=$file table=$table id=$id"
    conflict=1
  fi
done < "$tmp_candidates"

if [ "$conflict" -ne 0 ]; then
  echo "[ERROR] Precheck SQL world IDs echoue. Provisioning bloque."
  exit 1
fi

echo "[OK] Precheck SQL world IDs termine sans conflit detecte."
