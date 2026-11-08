# History & decision log

How ROTTEN_SERVER was built, in order: what was decided, why, and what went wrong along the way.

## Goals

1. Play a modded Minecraft pack from home **and** from anywhere.
2. Turn a spare mini PC into a real homelab: low power, learn DevOps-style ops.
3. Expose nothing to the Internet.

## Decisions

| Question | Options considered | Choice | Why |
|---|---|---|---|
| Base OS | Proxmox, Debian | **Debian 13, bare metal** | One small box: a hypervisor adds overhead and complexity for no gain. Docker gives the isolation needed. |
| Minecraft management | Crafty, Pterodactyl, itzg image | **`itzg/minecraft-server`** | Installs a `.mrpack` directly, skips client-only mods, whole config in one compose file. Pterodactyl is overkill (DB + Redis + panel + agent). |
| Remote access | Port forwarding + DynDNS, Tailscale | **Tailscale** | Works anywhere, even behind CGNAT, with nothing exposed. SSH keeps working as usual, through the tunnel. |
| Domain | none (MagicDNS only), buy one | **rotten-guy.com at OVH** | Clean names + real HTTPS certificates for ~10 €/year. `.com` over `.fr` for universality. |
| Reverse proxy | Caddy, Traefik, Nginx Proxy Manager | **Nginx Proxy Manager** | GUI matches the Dockge workflow, and it has a built-in OVH DNS-01 plugin (needed: the server isn't reachable for HTTP-01). |
| Container UI | Portainer, Dockge | **Dockge** | Stacks stay plain `compose.yaml` files on disk (Git-friendly), lightweight. |
| DNS strategy | split-horizon, LAN rewrites, Tailscale IP | **public wildcard → Tailscale IP** | One record serves every service; names only resolve to something reachable for tailnet members. |
| Ad blocking scope | LAN only (router DNS), tailnet | **Tailscale global nameserver** | Ad blocking follows every device, including on 4G. |
| Off-server backups | manual rsync, timer pull | **desktop pulls daily with a restricted key** | Pull model (the server can't touch the desktop), no `--delete` so a wiped server can't wipe the copy. |

## Timeline

### 2026-11-07: from idea to running services

1. **Plan**: Debian + Docker + itzg + Tailscale. Hardware turned out to be a *ThinkCentre M73 Tiny* (Celeron G1840T, 6 GB), not a NUC. Fine for services, tight for a 142-mod pack.
2. **Domain**: bought `rotten-guy.com` at OVH. The ICANN owner-verification email has to be clicked within 15 days.
3. **Repo**: `ROTTEN_SERVER` created; `setup.sh` bootstraps everything and copies stacks to `/opt/stacks` for Dockge.
4. **OS**: Debian 13 netinst, SSH only. Ran `setup.sh`: Docker 29, Tailscale, ufw, unattended-upgrades, powertop, Dockge up.
5. **Tailscale**: server + desktop + phone on the tailnet, key expiry disabled on the server.
6. **DNS**: OVH `*` A record → server's Tailscale IP. Verified with `ping test.rotten-guy.com`.
7. **TLS**: OVH API key (scoped to the zone) → NPM *Let's Encrypt via DNS* → wildcard `*.rotten-guy.com` + apex, ECDSA, auto-renewing.
8. **Proxy hosts**: dockge, proxy, adguard, vault, all over HTTPS.
9. **AdGuard**: admin UI on 3000 (80 belongs to NPM), set as the tailnet's global nameserver. `doubleclick.net → 0.0.0.0` confirmed.

### 2026-11-08: vault, backups, Minecraft

10. **Vaultwarden**: account created, sign-ups closed, Bitwarden apps on desktop and phone (self-hosted URL).
11. **Backups**: `backup.sh` (vault + every config, nightly, 30 days) and a desktop systemd timer pulling `/opt/backups` daily, through a passphrase-less key locked to `rrsync -ro`. Tested end to end.
12. **Minecraft**: server-only pack (configs, mods, datapacks; no resource or shader packs) uploaded; compose writes world backups to `/opt/backups/minecraft`.
13. **Docs**: everything translated to English; setup, migration, backups, history and roadmap written.
14. **Minecraft live**: server up in ~57 s, existing Hardcore world restored, 64 datapacks active (all mod-provided), first world backup pulled to the desktop. Chunky pre-generation (radius 2000) started.
15. **Desktop leaves the tailnet**: Discord voice (Vesktop) failed at the DTLS step whenever Tailscale was up on the Arch desktop, even with no exit node, `--accept-dns=false` and `--netfilter-mode=off`. Root cause not found. Since the desktop never leaves home, it now reaches the server over the **LAN** via `/etc/hosts` instead, and `tailscaled` is disabled there. Tailscale stays on mobile devices.
16. **SSH hardened**: key-only, no root login; password login verified refused, backup key still working.
17. **OVH key rotation postponed**: NPM 2.16 stores DNS-challenge credentials in its database (the `credentials-N` file only exists during renewals), so rotation means re-issuing the certificate. Risk accepted for now; see ROADMAP.
18. **Minecraft world restored properly**: the first copy had produced a new seed (the server didn't find the world, so it generated one). Fixed by stopping the stack, placing the folder containing `level.dat` as `data/world`, removing `session.lock`, `chown 1000:1000`. Seed verified, player data intact.
19. **World backups resized** for a pre-generated world: every 12 h, 3 days on the server, 14 days on the desktop, zstd compression.
20. **Portfolio on rotten-guy.com**: GitHub Pages custom domain (CNAME file via PR), OVH parking records replaced by GitHub's A/AAAA + `www` CNAME. Private services keep working: the `*` wildcard doesn't cover the apex.
21. **Git sync**: `scripts/stacks.sh` imports Dockge edits into the repo and exports repo changes to `/opt/stacks` (compose files only).

## Gotchas (lessons learned)

| Symptom | Cause | Fix |
|---|---|---|
| `rotten-guy is not in the sudoers file` right after `usermod -aG sudo` | groups are read at login; `exit` from `su` returns to the **old** session | log out completely / reboot |
| `reboot: command not found` as root | `su` without `-` keeps the user's PATH (no `/usr/sbin`) | `su -` or `systemctl reboot` |
| `tailscale up` "context canceled" | Ctrl+C before finishing the browser login | rerun, complete login, wait for `Success.` |
| NPM v2.16: "no DNS challenge checkbox" | new UI: *Add Certificate → Let's Encrypt via DNS* **is** the DNS challenge | pick the provider in that form |
| First certificate takes minutes | NPM installs the certbot OVH plugin on first use + 120 s propagation | wait; `docker logs -f npm` |
| `502 Bad Gateway` on vault | the container was stopped, so NPM had nothing to reach | **Deploy** (not *Save*) in Dockge |
| Bitwarden Android: timeout to `100.x` from `192.168.x` | Tailscale off on the phone | install Tailscale, enable Always-on VPN |
| Backup timer: `Permission denied (publickey)` | main key has a passphrase; a timer can't type it | dedicated key restricted with `rrsync -ro` |
| SFTP can't write to `/opt/stacks` | `/opt` belongs to root | upload to `~`, then `sudo mv` |
| Discord voice stuck on "DTLS connection" on the desktop | unknown interaction between Tailscale and Vesktop's WebRTC on Arch (not DNS, not exit node, not netfilter) | desktop off the tailnet, LAN + `/etc/hosts` (see SETUP § Clients at home) |
| Minecraft backups never pruned on the desktop | mc-backup writes `.tar.gz`, the pull script only pruned `.tgz` | prune both extensions |
| Restored world has a different seed | server didn't find `data/world/level.dat` (wrong folder level / copied while running), so it generated a new world | stop stack, folder containing `level.dat` → `data/world`, `chown -R 1000:1000` |
| `ssh rotten-guy@rotten-server …` refused while already on the server | ran it *on* the server, which has no key for itself | run the command directly, without `ssh` |
| Termius locked out after SSH hardening | the Termius host was using a password; its key slot was empty | generate a key in Termius, append its public key to `authorized_keys` |
| OVH refuses an empty subdomain | this OVH UI needs `@` for the domain root | use `@` |
| `chunky continue`: "No tasks to continue" | the task was already running (nothing paused) | check with `chunky progress` |
| OVH refuses an empty subdomain | this UI needs `@` for the apex | use `@` |
| GitHub Pages "Custom domain" empty after DNS change | the `CNAME` PR wasn't merged yet | merge it; don't type the domain in Settings (it would commit a conflicting `CNAME`) |
| `chunky continue` → "No tasks to continue" | the task was still running, nothing paused | check with `chunky progress` |
| `credentials-1` opens as "New File" in nano | NPM 2.16 keeps DNS credentials in its SQLite DB, writes the file only during renewal | rotate by issuing a new certificate (ROADMAP) |
| Archives dated "yesterday" around midnight | server clock in UTC | `timedatectl set-timezone Europe/Paris` (now in `setup.sh`) |

## Security incidents

- **OVH API key visible in screenshots** shared during setup. Scope is limited to the DNS zone, but the key is still being rotated (see [ROADMAP](ROADMAP.md)). Rule since then: never screenshot secrets.
