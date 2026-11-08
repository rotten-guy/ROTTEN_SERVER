#!/usr/bin/env bash
# Nightly server backup -> /opt/backups
# Installed as /etc/cron.daily/homelab-backup (see docs/BACKUPS.md)
#
#   /opt/backups/
#   ├── vaultwarden/   password vault (database, keys, attachments)
#   ├── config/        every stack's config (proxy + certs, AdGuard, Dockge, .env files)
#   └── minecraft/     written directly by the mc-backup container
#
# ⚠️ These archives contain secrets (.env files, OVH API key, encrypted vault):
#    they are readable by rotten-guy only.
set -euo pipefail
DEST=/opt/backups
OWNER=rotten-guy
DATE=$(date +%F)
KEEP_DAYS=30
mkdir -p "$DEST/vaultwarden" "$DEST/config" "$DEST/minecraft"

# --- Vaultwarden -------------------------------------------------------------
VW=/opt/stacks/vaultwarden/data
if [ -d "$VW" ]; then
  # Consistent SQLite snapshot (data/db_<timestamp>.sqlite3) if the container is running
  docker exec vaultwarden /vaultwarden backup >/dev/null 2>&1 \
    || echo "warning: live SQLite backup failed, archiving the raw database file"
  tar -czf "$DEST/vaultwarden/vaultwarden-$DATE.tgz" -C "$VW" --exclude=icon_cache .
  find "$VW" -maxdepth 1 -name 'db_*.sqlite3' -delete
fi

# --- Configuration -----------------------------------------------------------
tar -czf "$DEST/config/config-$DATE.tgz" -C /opt \
  --exclude=stacks/minecraft/data \
  --exclude=stacks/minecraft/modpacks \
  --exclude=stacks/vaultwarden/data \
  --exclude=stacks/adguard/work \
  stacks dockge

# --- Rotation + permissions --------------------------------------------------
find "$DEST/vaultwarden" "$DEST/config" -name '*.tgz' -mtime +"$KEEP_DAYS" -delete
chown -R "$OWNER:$OWNER" "$DEST"
chmod -R u=rwX,go= "$DEST"
echo "Backup OK: $(du -sh "$DEST" | cut -f1) in $DEST"
