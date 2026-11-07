#!/usr/bin/env bash
# Sauvegarde nocturne du serveur -> /opt/backups
# Installé dans /etc/cron.daily/homelab-backup (voir README, « Sauvegardes »)
#
#   /opt/backups/
#   ├── vaultwarden/   coffre de mots de passe (base + clés + pièces jointes)
#   ├── config/        configs de toutes les stacks (proxy, certificats, AdGuard, Dockge, .env)
#   └── minecraft/     écrit directement par le conteneur mc-backup
#
# ⚠️ Ces archives contiennent des secrets (.env, clé API OVH, coffre chiffré) :
#    elles ne sont lisibles que par rotten-guy.
set -euo pipefail
DEST=/opt/backups
OWNER=rotten-guy
DATE=$(date +%F)
KEEP_DAYS=30
mkdir -p "$DEST/vaultwarden" "$DEST/config" "$DEST/minecraft"

# --- Vaultwarden -------------------------------------------------------------
VW=/opt/stacks/vaultwarden/data
if [ -d "$VW" ]; then
  # Copie cohérente de la base SQLite si le conteneur tourne
  docker exec vaultwarden /vaultwarden backup >/dev/null 2>&1 \
    || echo "avertissement : backup SQLite à chaud impossible, copie du fichier brut"
  tar -czf "$DEST/vaultwarden/vaultwarden-$DATE.tgz" -C "$VW" --exclude=icon_cache .
  find "$VW" -maxdepth 1 -name 'db_*.sqlite3' -delete
fi

# --- Configurations ----------------------------------------------------------
tar -czf "$DEST/config/config-$DATE.tgz" -C /opt \
  --exclude=stacks/minecraft/data \
  --exclude=stacks/minecraft/modpacks \
  --exclude=stacks/vaultwarden/data \
  --exclude=stacks/adguard/work \
  stacks dockge

# --- Rotation + droits -------------------------------------------------------
find "$DEST/vaultwarden" "$DEST/config" -name '*.tgz' -mtime +"$KEEP_DAYS" -delete
chown -R "$OWNER:$OWNER" "$DEST"
chmod -R u=rwX,go= "$DEST"
echo "Sauvegarde OK : $(du -sh "$DEST" | cut -f1) dans $DEST"
