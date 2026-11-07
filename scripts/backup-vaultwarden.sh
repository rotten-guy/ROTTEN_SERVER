#!/usr/bin/env bash
# Sauvegarde quotidienne de Vaultwarden (installé par setup.sh dans /etc/cron.daily)
set -euo pipefail
SRC=/opt/stacks/vaultwarden/data
DEST=/opt/backups/vaultwarden
mkdir -p "$DEST"

# Copie cohérente de la base SQLite (crée data/db_AAAAMMJJ_HHMMSS.sqlite3)
docker exec vaultwarden /vaultwarden backup

tar -czf "$DEST/vaultwarden-$(date +%F).tgz" -C "$SRC" --exclude=icon_cache .

# Ménage : copies SQLite intermédiaires et archives de plus de 30 jours
find "$SRC" -maxdepth 1 -name 'db_*.sqlite3' -delete
find "$DEST" -name 'vaultwarden-*.tgz' -mtime +30 -delete
