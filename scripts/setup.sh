#!/usr/bin/env bash
# Préparation du serveur (Debian 13). À lancer depuis la racine du dépôt :
#   sudo bash scripts/setup.sh <ton_utilisateur>
set -euo pipefail
USER_NAME="${1:?Usage: sudo bash scripts/setup.sh <utilisateur>}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Paquets de base + mises à jour de sécurité automatiques"
apt-get update
apt-get install -y curl git ufw unattended-upgrades htop powertop
dpkg-reconfigure -f noninteractive unattended-upgrades

echo "==> Docker"
command -v docker >/dev/null || curl -fsSL https://get.docker.com | sh
usermod -aG docker "$USER_NAME"

echo "==> Tailscale"
command -v tailscale >/dev/null || curl -fsSL https://tailscale.com/install.sh | sh

echo "==> Pare-feu (protège les services de l'hôte, ex. SSH)"
# Docker publie ses ports en contournant ufw : sans danger tant qu'AUCUN port
# n'est redirigé sur la box.
ufw default deny incoming
ufw default allow outgoing
ufw allow in on tailscale0
ufw allow from 192.168.0.0/16 to any port 22 proto tcp
ufw --force enable

echo "==> Économie d'énergie"
cat > /etc/systemd/system/powertop.service <<'UNIT'
[Unit]
Description=Powertop auto-tune
[Service]
Type=oneshot
ExecStart=/usr/sbin/powertop --auto-tune
[Install]
WantedBy=multi-user.target
UNIT
systemctl enable --now powertop.service

echo "==> Réseau Docker partagé 'proxy'"
docker network inspect proxy >/dev/null 2>&1 || docker network create proxy

echo "==> Stacks dans /opt/stacks (fichiers existants conservés)"
mkdir -p /opt/stacks /opt/dockge /opt/backups
cp -rn "$REPO/stacks/." /opt/stacks/
cp -n "$REPO/dockge/compose.yaml" /opt/dockge/compose.yaml

echo "==> Sauvegarde nocturne (/opt/backups)"
apt-get install -y rsync
install -m 755 "$REPO/scripts/backup.sh" /etc/cron.daily/homelab-backup

echo "==> Démarrage de Dockge"
docker compose -f /opt/dockge/compose.yaml up -d

IP=$(hostname -I | awk '{print $1}')
echo
echo "Terminé ! Dockge : http://$IP:5001"
echo "Ensuite : sudo tailscale up --accept-dns=false   (voir README, étape 2)"
echo "Déconnecte-toi / reconnecte-toi pour utiliser docker sans sudo."
