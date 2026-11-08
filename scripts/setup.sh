#!/usr/bin/env bash
# Bootstrap a fresh Debian 13 server for ROTTEN_SERVER. Run from the repo root:
#   sudo bash scripts/setup.sh <your_user>
# Idempotent: safe to re-run. Never overwrites existing files in /opt.
set -euo pipefail
USER_NAME="${1:?Usage: sudo bash scripts/setup.sh <user>}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Base packages + automatic security updates"
apt-get update
apt-get install -y curl git rsync ufw unattended-upgrades htop powertop
dpkg-reconfigure -f noninteractive unattended-upgrades
timedatectl set-timezone Europe/Paris

echo "==> Docker"
command -v docker >/dev/null || curl -fsSL https://get.docker.com | sh
usermod -aG docker "$USER_NAME"

echo "==> Tailscale"
command -v tailscale >/dev/null || curl -fsSL https://tailscale.com/install.sh | sh

echo "==> Firewall (protects host services such as SSH)"
# Docker-published ports bypass ufw: harmless as long as NO port is
# forwarded on the router.
ufw default deny incoming
ufw default allow outgoing
ufw allow in on tailscale0
ufw allow from 192.168.0.0/16 to any port 22 proto tcp
ufw --force enable

echo "==> Power saving"
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

echo "==> Shared Docker network 'proxy'"
docker network inspect proxy >/dev/null 2>&1 || docker network create proxy

echo "==> Stacks to /opt/stacks (existing files are kept)"
mkdir -p /opt/stacks /opt/dockge /opt/backups
cp -rn "$REPO/stacks/." /opt/stacks/
cp -n "$REPO/dockge/compose.yaml" /opt/dockge/compose.yaml

echo "==> Nightly backup (/opt/backups)"
install -m 755 "$REPO/scripts/backup.sh" /etc/cron.daily/homelab-backup

echo "==> Starting Dockge"
docker compose -f /opt/dockge/compose.yaml up -d

IP=$(hostname -I | awk '{print $1}')
echo
echo "Done! Dockge: http://$IP:5001"
echo "Next: sudo tailscale up --accept-dns=false   (see docs/SETUP.md)"
echo "Log out and back in to use docker without sudo."
