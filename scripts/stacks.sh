#!/usr/bin/env bash
# Keep the repo and the live stacks in sync. Compose files only:
# never .env files, never data. Run on the server, as rotten-guy, from anywhere.
#
#   scripts/stacks.sh status   what differs between the repo and /opt (live)
#   scripts/stacks.sh import   live -> repo   (after editing in Dockge), then commit + push
#   scripts/stacks.sh export   repo -> live   (after a git pull), then Deploy in Dockge
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
LIVE=/opt/stacks
command -v rsync >/dev/null || { echo "rsync is missing: sudo apt install rsync" >&2; exit 1; }
# Data/secret folders are skipped entirely; only compose.yaml and .env.example travel.
RULES=(--exclude=data/ --exclude=letsencrypt/ --exclude=work/ --exclude=conf/
       --exclude=modpacks/ --exclude=backups/
       --include='*/' --include=compose.yaml --include=.env.example --exclude='*'
       --prune-empty-dirs)

changed() {  # files under $LIVE whose content differs from the repo
  rsync -rcn --out-format='%n' "${RULES[@]}" "$LIVE/" "$REPO/stacks/" | grep -v '/$' || true
}

case "${1:-status}" in
  status)
    files=$(changed)
    cmp -s /opt/dockge/compose.yaml "$REPO/dockge/compose.yaml" || files="$files"$'\n'"(dockge) compose.yaml"
    if [ -z "${files//[$'\n ']/}" ]; then echo "In sync: repo == live."; exit 0; fi
    echo "Differs between repo and live:"
    for f in $(changed); do
      echo; echo "=== stacks/$f   (--- repo  +++ live)"
      diff -u "$REPO/stacks/$f" "$LIVE/$f" 2>/dev/null || [ -e "$REPO/stacks/$f" ] || echo "(new on live, not in repo yet)"
    done
    if ! cmp -s /opt/dockge/compose.yaml "$REPO/dockge/compose.yaml"; then
      echo; echo "=== dockge/compose.yaml   (--- repo  +++ live)"
      diff -u "$REPO/dockge/compose.yaml" /opt/dockge/compose.yaml || true
    fi
    echo; echo "import = keep live (then commit)  ·  export = keep repo (then Deploy)"
    ;;
  import)
    rsync -rc "${RULES[@]}" "$LIVE/" "$REPO/stacks/"
    cp /opt/dockge/compose.yaml "$REPO/dockge/compose.yaml"
    git -C "$REPO" status --short
    echo "Now: git -C $REPO add -A && git -C $REPO commit -m '...' && git -C $REPO push"
    ;;
  export)
    sudo rsync -rc "${RULES[@]}" "$REPO/stacks/" "$LIVE/"
    sudo cp "$REPO/dockge/compose.yaml" /opt/dockge/compose.yaml
    echo "Live files updated. Redeploy the changed stacks in Dockge."
    ;;
  *) echo "usage: $0 status|import|export" >&2; exit 2 ;;
esac
