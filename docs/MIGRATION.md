# Migration to new hardware

Move the whole homelab (configs, certificates, vault, Minecraft world) to another machine. Everything is Docker + plain files, so migrating means **reinstall, restore, and re-point two IPs**.

Expected downtime: ~1 hour. All images used are multi-arch, so the target can be x86_64 **or** ARM64 (e.g. a Raspberry Pi 5).

## Overview

```
 old server ──(final backup)──► desktop ──(scp)──► new server
                                                    │ setup.sh
                                                    │ restore config + vault + world
                                                    │ tailscale up
 OVH DNS  *.rotten-guy.com ──────────────────────►  new Tailscale IP
 Tailscale global nameserver ────────────────────►  new Tailscale IP
```

The only things tied to the hardware are the **Tailscale IP** (DNS record + tailnet nameserver) and the **SSH host key** (clients will warn once). Certificates, proxy hosts, accounts and settings all travel inside the backups.

## 1. Final backup on the old server

Skip this section if the old server is dead and use the latest archives already on the desktop.

1. Stop Minecraft cleanly so the world is consistent:
   ```bash
   docker exec minecraft rcon-cli "save-all flush"
   ```
   ```bash
   docker exec minecraft-backup backup now
   ```
2. Run the nightly backup immediately:
   ```bash
   sudo /etc/cron.daily/homelab-backup
   ```
3. Pull everything to the desktop:
   ```bash
   systemctl --user start rotten-backup.service && ls -lhR ~/backups/rotten-server
   ```
4. Stop all stacks in Dockge, so nothing changes after the backup.
5. Keep a copy of the server `.mrpack` on the desktop: it is excluded from backups and from Git.

## 2. Prepare the new machine

Follow [SETUP.md](SETUP.md) **steps 1 to 5 only** (BIOS, Debian, router lease, SSH keys, `setup.sh`).
Stop before deploying any stack: restoring must happen **before** the first deploy.

`setup.sh` copies template stacks to `/opt/stacks` and starts an empty Dockge. Both get overwritten by the restore.

## 3. Restore

From the desktop, send the latest archives (replace `<date>`):

```bash
cd ~/backups/rotten-server && scp config/config-<date>.tgz vaultwarden/vaultwarden-<date>.tgz rotten-guy@<new-server-lan-ip>:~/
```

```bash
scp "$(ls -t ~/backups/rotten-server/minecraft/*.tar.gz | head -1)" rotten-guy@<new-server-lan-ip>:~/minecraft-latest.tgz
```

```bash
scp ~/rotten_adventurer_modpack_for_server.mrpack rotten-guy@<new-server-lan-ip>:~/pack.mrpack
```

On the new server, stop the fresh Dockge and restore all configuration:

```bash
docker compose -f /opt/dockge/compose.yaml down
```

```bash
sudo tar -xzf ~/config-*.tgz -C /opt
```

Vaultwarden data:

```bash
sudo mkdir -p /opt/stacks/vaultwarden/data && sudo tar -xzf ~/vaultwarden-*.tgz -C /opt/stacks/vaultwarden/data
```

```bash
cd /opt/stacks/vaultwarden/data && ls db_*.sqlite3 && sudo mv db_*.sqlite3 db.sqlite3 && sudo rm -f db.sqlite3-wal db.sqlite3-shm
```

Minecraft world + pack:

```bash
sudo mkdir -p /opt/stacks/minecraft/data /opt/stacks/minecraft/modpacks && sudo tar -xzf ~/minecraft-latest.tgz -C /opt/stacks/minecraft/data
```

```bash
sudo mv ~/pack.mrpack /opt/stacks/minecraft/modpacks/pack.mrpack
```

Restart Dockge (it gets back its accounts from the restored `/opt/dockge/data`):

```bash
docker compose -f /opt/dockge/compose.yaml up -d
```

## 4. Tailscale

1. In the Tailscale admin console, **remove the old `rotten-server`** machine, or rename it (e.g. `rotten-server-old`) so the name is free.
2. On the new server:
   ```bash
   sudo tailscale up --accept-dns=false --hostname=rotten-server
   ```
3. **Disable key expiry** for the new machine and note its IP:
   ```bash
   tailscale ip -4
   ```

## 5. Re-point the two IPs

| Where | Change |
|---|---|
| OVH → DNS zone → `*` A record | new Tailscale IP |
| Tailscale admin → DNS → Global nameservers | replace the old IP with the new one |

From a client, wait a few minutes, then check:

```bash
ping test.rotten-guy.com
```

## 6. Deploy

In Dockge, **Deploy** in order: **proxy → adguard → vaultwarden → minecraft**.
Nothing needs re-configuring: NPM proxy hosts + the wildcard certificate, AdGuard settings, Vaultwarden accounts and `.env` files are all restored.

The certificate's OVH credentials are restored too, so automatic renewal keeps working.

## 7. Clients & housekeeping

- SSH host key changed: on each client, run this once, then reconnect and accept the new fingerprint:
  ```bash
  ssh-keygen -R rotten-server
  ```
  In Termius, accept the new fingerprint.
- Desktop backup key: re-authorize it on the new server ([BACKUPS.md → dedicated key](BACKUPS.md#dedicated-restricted-key-once), the `echo … >> authorized_keys` command), then test the timer.
- Re-run the hardening step ([SETUP.md § 11](SETUP.md#11-harden-ssh)).
- Re-apply the router's static DHCP lease for the new MAC address.
- Run through the [SETUP.md done checklist](SETUP.md#done-checklist).
- Keep the old machine untouched for a week before wiping it.

## Hardware-specific values to revisit

| Value | File | Why |
|---|---|---|
| `MC_MEMORY` | minecraft `.env` | scale with RAM (16 GB → `8G`) |
| `VIEW_DISTANCE`, `SIMULATION_DISTANCE`, `MAX_PLAYERS` | `stacks/minecraft/compose.yaml` | raise on a faster CPU |
| `image: …:java21` | `stacks/minecraft/compose.yaml` | follow the pack's Minecraft version |
| `192.168.0.0/16` | `scripts/setup.sh` (ufw) | if the LAN range changes |
