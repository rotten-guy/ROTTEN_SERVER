#!/usr/bin/env bash
# Desktop side: pulls the server's /opt/backups over SSH (through Tailscale).
# No --delete on purpose: if the server gets wiped, the local copy survives.
#
# Uses a dedicated passphrase-less key (~/.ssh/rotten_backup), restricted on
# the server to read-only access to /opt/backups via rrsync (see docs/BACKUPS.md).
# The remote path is therefore relative to /opt/backups: "./" = /opt/backups/.
set -euo pipefail
KEY="$HOME/.ssh/rotten_backup"
SRC="rotten-guy@rotten-server:./"
DEST="$HOME/backups/rotten-server"
KEEP_DAYS=90

mkdir -p "$DEST"
# Exit code 23/24 = some files unreadable or vanished mid-transfer (e.g. a
# Minecraft backup being written): keep going, they'll be picked up next time.
rsync -a --partial -e "ssh -i $KEY -o IdentitiesOnly=yes -o BatchMode=yes" "$SRC" "$DEST/" || { rc=$?; [ $rc -eq 23 ] || [ $rc -eq 24 ] || exit $rc; echo "warning: partial transfer (code $rc)"; }
find "$DEST" \( -name '*.tgz' -o -name '*.tar.gz' \) -mtime +"$KEEP_DAYS" -delete
echo "Backups up to date in $DEST ($(du -sh "$DEST" | cut -f1))"
