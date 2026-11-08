# ROTTEN_SERVER

Self-hosted homelab behind **rotten-guy.com**: a low-power mini PC running Docker stacks, reachable from anywhere through Tailscale, with **zero ports opened on the router**.

```
rotten-server — Lenovo ThinkCentre M73 Tiny · Debian 13 (trixie)
├── Tailscale ........... private mesh VPN — the only way in from outside
├── OpenSSH ............. key-only, reachable over LAN + Tailscale
└── Docker (managed with Dockge)
    ├── proxy ........... Nginx Proxy Manager + wildcard Let's Encrypt cert
    ├── adguard ......... DNS + ad blocking for every device on the tailnet
    ├── vaultwarden ..... password manager (Bitwarden-compatible)
    └── minecraft ....... modded Hardcore server + automatic world backups
```

| Service | URL | Notes |
|---|---|---|
| Dockge | https://dockge.rotten-guy.com | manage every stack |
| Nginx Proxy Manager | https://proxy.rotten-guy.com | proxy hosts + certificates |
| AdGuard Home | https://adguard.rotten-guy.com | tailnet-wide DNS / ad blocking |
| Vaultwarden | https://vault.rotten-guy.com | Bitwarden apps → *self-hosted* |
| Minecraft | `mc.rotten-guy.com` | default port 25565 |
| Portfolio (public) | https://rotten-guy.com | GitHub Pages, not hosted here |

All `*.rotten-guy.com` subdomains resolve to the server's **Tailscale IP**, so they only work on devices logged into the tailnet. Nothing is exposed to the Internet.

## How it fits together

```
 phone / laptop / desktop                       rotten-server
 ┌──────────────────────┐  Tailscale (WireGuard)  ┌──────────────────────────────┐
 │ vault.rotten-guy.com │ ──────────────────────► │ :443 Nginx Proxy Manager     │
 │  DNS: *.rotten-guy   │                         │   ├─ vaultwarden:80          │
 │  .com → Tailscale IP │                         │   ├─ dockge:5001             │
 └──────────────────────┘                         │   ├─ adguard:3000            │
          ▲                                       │   └─ npm:81                  │
          │ DNS queries (Tailscale global NS)     │ :53    AdGuard Home          │
          └────────────────────────────────────── │ :25565 Minecraft             │
                                                  └──────────────────────────────┘
 OVH DNS : *.rotten-guy.com  A  <Tailscale IP>    (public record, private target)
           rotten-guy.com / www → GitHub Pages     (public portfolio)
 TLS     : Let's Encrypt wildcard via OVH DNS-01  (no inbound HTTP needed)
```

## Repository layout

```
ROTTEN_SERVER/
├── README.md
├── docs/
│   ├── SETUP.md           # build the server from scratch, step by step
│   ├── MIGRATION.md       # move everything to new hardware using the backups
│   ├── BACKUPS.md         # what is backed up, where, and how to restore
│   ├── HISTORY.md         # what was built, in order, and why (decision log)
│   └── ROADMAP.md         # done / next / ideas
├── scripts/
│   ├── setup.sh           # bootstrap a fresh Debian (Docker, Tailscale, ufw, Dockge…)
│   ├── backup.sh          # nightly backup → /opt/backups (cron.daily)
│   └── stacks.sh          # sync compose files between the repo and /opt (status/import/export)
├── desktop/               # desktop side: daily pull of the backups (systemd user timer)
├── dockge/compose.yaml    # → /opt/dockge
└── stacks/                # → /opt/stacks (one folder = one Dockge stack)
    ├── proxy/  adguard/  vaultwarden/  minecraft/
```

Secrets (`.env`, certificates, API keys) and data never go into Git; they are covered by the [backups](docs/BACKUPS.md).

## Day-to-day

| Task | How |
|---|---|
| Edit / restart / update a stack | Dockge → stack → *Edit* / *Restart* / *Update* |
| Save Dockge edits to GitHub | `~/ROTTEN_SERVER/scripts/stacks.sh import` → `git commit` → `git push` ([details](docs/SETUP.md#12-keep-git-in-sync)) |
| Apply repo changes to the server | `git pull` → `scripts/stacks.sh export` → *Deploy* in Dockge |
| Add a web service | new stack on the `proxy` network → NPM *Proxy Host* `<name>.rotten-guy.com` + wildcard cert |
| Minecraft console | `docker exec -it minecraft rcon-cli` |
| Backup now | `sudo /etc/cron.daily/homelab-backup` · `docker exec minecraft-backup backup now` |
| Pull backups to the desktop now | `systemctl --user start rotten-backup.service` (on the desktop) |
| Check what's running | `docker ps` · `htop` |
| Emergency: DNS broken because the server is down | desktop: `sudo tailscale set --accept-dns=false` · phone: turn Tailscale off |

## Security model

- **No port forwarding** on the router. Remote access exists only through Tailscale.
- SSH: public keys only, no root login. The backup key is locked to read-only `rsync` of `/opt/backups`.
- `ufw` denies inbound by default (LAN SSH + `tailscale0` allowed).
- Automatic Debian security updates (`unattended-upgrades`).
- Vaultwarden sign-ups disabled once the account exists.

## Hardware

| | Current | Notes |
|---|---|---|
| Machine | ThinkCentre M73 Tiny (10AXS6AY00) | low idle power draw |
| CPU | Intel Celeron G1840T, 2C/2T @ 2.5 GHz | main bottleneck for modded Minecraft |
| RAM | 6 GB DDR3L | 3 GB for Minecraft |
| Disk | 450 GB SSD, ext4 | |
| Network | Ethernet, static DHCP lease `192.168.1.107` (Bbox) | |

Cheap upgrade path: see [ROADMAP](docs/ROADMAP.md#hardware).
