#!/usr/bin/env bash
# À installer sur ton PC : récupère /opt/backups du serveur via SSH (Tailscale).
# Pas de --delete : si le serveur est effacé, ta copie locale reste intacte.
#
# Utilise une clé dédiée sans phrase de passe (~/.ssh/rotten_backup), bridée
# côté serveur en lecture seule sur /opt/backups via rrsync (voir README).
# Le chemin distant est donc relatif à /opt/backups : « ./ » = /opt/backups/.
set -euo pipefail
KEY="$HOME/.ssh/rotten_backup"
SRC="rotten-guy@rotten-server:./"
DEST="$HOME/backups/rotten-server"
KEEP_DAYS=90

mkdir -p "$DEST"
# Code 23/24 = quelques fichiers illisibles ou disparus pendant la copie
# (ex. backup Minecraft en cours) : on continue, ils seront pris la prochaine fois.
rsync -a --partial -e "ssh -i $KEY -o IdentitiesOnly=yes -o BatchMode=yes" "$SRC" "$DEST/" || { rc=$?; [ $rc -eq 23 ] || [ $rc -eq 24 ] || exit $rc; echo "avertissement : copie partielle (code $rc)"; }
find "$DEST" -name '*.tgz' -mtime +"$KEEP_DAYS" -delete
echo "Backups à jour dans $DEST ($(du -sh "$DEST" | cut -f1))"
