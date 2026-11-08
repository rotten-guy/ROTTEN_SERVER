# Backups & restore

```
rotten-server                                   rotten-desktop
/opt/backups/                                   ~/backups/rotten-server/
├── vaultwarden/  nightly (cron)        ──►     daily pull at 12:00 (systemd user timer)
├── config/       nightly (cron)                kept 90 days, never deleted
└── minecraft/    every 6 h (mc-backup)         even if the server is wiped
   kept 30 days (Minecraft: 7)
```

| Archive | Contents | Produced by |
|---|---|---|
| `vaultwarden/vaultwarden-<date>.tgz` | Vaultwarden `data/`: live SQLite snapshot + raw DB, RSA keys, attachments, config | `scripts/backup.sh` |
| `config/config-<date>.tgz` | `/opt/stacks` + `/opt/dockge`: compose files, `.env` files, NPM database + Let's Encrypt certs + OVH credentials, AdGuard config, Dockge accounts | `scripts/backup.sh` |
| `minecraft/world-<date>-<time>.tar.gz` | the whole Minecraft `/data` (world, configs, mods), excluding jars and caches | `itzg/mc-backup` |

Excluded on purpose: the Minecraft data from `config/` (it has its own backups), AdGuard query logs, the Vaultwarden icon cache, and the modpack file (re-uploadable).

> ⚠️ Archives contain secrets. They are `chmod 600`, owned by `rotten-guy`, on both machines.

## Server side

Installed by `setup.sh`. To (re)install manually:

```bash
cd ~/ROTTEN_SERVER && git pull && sudo install -m 755 scripts/backup.sh /etc/cron.daily/homelab-backup
```

Run it now and check the result:

```bash
sudo /etc/cron.daily/homelab-backup && ls -lhR /opt/backups
```

`cron.daily` runs around 06:25 (Debian default). The Minecraft stack must mount `/opt/backups/minecraft:/backups` for its backups to be pulled.

## Desktop side (Arch)

```bash
sudo pacman -S --needed rsync
```

```bash
git clone https://github.com/rotten-guy/ROTTEN_SERVER.git ~/ROTTEN_SERVER
```

```bash
install -Dm755 ~/ROTTEN_SERVER/desktop/pull-backups.sh ~/.local/bin/pull-backups.sh
```

```bash
install -Dm644 -t ~/.config/systemd/user ~/ROTTEN_SERVER/desktop/rotten-backup.{service,timer}
```

```bash
systemctl --user daemon-reload && systemctl --user enable --now rotten-backup.timer
```

### Dedicated restricted key (once)

The timer runs unattended, so it can't type your main key's passphrase. It gets its own key: **no passphrase, but locked server-side** to read-only `rsync` of `/opt/backups` through `rrsync` (no shell, no writes, no other path).

```bash
ssh-keygen -t ed25519 -N "" -C "backup@rotten-desktop" -f ~/.ssh/rotten_backup
```

```bash
echo "command=\"/usr/bin/rrsync -ro /opt/backups/\",restrict $(cat ~/.ssh/rotten_backup.pub)" | ssh rotten-guy@rotten-server 'cat >> ~/.ssh/authorized_keys'
```

This must be **refused**, with `PTY allocation request failed` / `rrsync error: Not invoked via sshd`:

```bash
ssh -i ~/.ssh/rotten_backup -o IdentitiesOnly=yes rotten-guy@rotten-server
```

### Test

```bash
systemctl --user start rotten-backup.service; journalctl --user -u rotten-backup -n 10 --no-pager
```

```bash
ls -lhR ~/backups/rotten-server
```

`Persistent=true`: if the desktop is off at noon, the pull runs at next boot.

## Restore

Copy archives back to the server first:

```bash
scp ~/backups/rotten-server/{config,vaultwarden}/*-<date>.tgz rotten-guy@rotten-server:~/
```

### Configuration (all stacks)

```bash
sudo tar -xzf ~/config-<date>.tgz -C /opt
```

This restores `/opt/stacks` and `/opt/dockge`, including `.env` files, NPM proxy hosts + certificates, AdGuard settings and Dockge accounts. Then redeploy the stacks.

### Vaultwarden

1. Dockge → vaultwarden → **Stop**.
2. Restore the data folder:
   ```bash
   sudo rm -rf /opt/stacks/vaultwarden/data && sudo mkdir -p /opt/stacks/vaultwarden/data
   ```
   ```bash
   sudo tar -xzf ~/vaultwarden-<date>.tgz -C /opt/stacks/vaultwarden/data
   ```
3. If a `db_<timestamp>.sqlite3` snapshot exists, it is the consistent copy: use it as the database.
   ```bash
   cd /opt/stacks/vaultwarden/data && ls db_*.sqlite3 && sudo mv db_*.sqlite3 db.sqlite3 && sudo rm -f db.sqlite3-wal db.sqlite3-shm
   ```
4. **Deploy**, log in, check your items.

### Minecraft world

1. Dockge → minecraft → **Stop**.
2. ```bash
   cd /opt/stacks/minecraft && sudo mv data/world data/world.old
   ```
   ```bash
   sudo tar -xzf /opt/backups/minecraft/world-<date>-<time>.tar.gz -C data
   ```
3. **Deploy**. Delete `world.old` once everything looks right.

## Extra safety nets

- Export the vault now and then: web vault → *Tools → Export vault*, **encrypted** format, stored somewhere else.
- A backup you've never restored is a hope, not a backup: run a [restore drill](ROADMAP.md) once.
- Both copies live in the same house: an off-site copy is on the roadmap (3-2-1 rule).
