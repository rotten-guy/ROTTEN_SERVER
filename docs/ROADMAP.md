# Roadmap

## ✅ Done

- [x] Debian 13 + Docker + Dockge, bootstrap script
- [x] Tailscale on server, desktop, phone (server key expiry disabled)
- [x] `rotten-guy.com` → wildcard DNS to the Tailscale IP
- [x] Nginx Proxy Manager + wildcard Let's Encrypt cert (OVH DNS-01)
- [x] AdGuard Home as tailnet-wide DNS / ad blocker
- [x] Vaultwarden + Bitwarden clients, sign-ups closed
- [x] Nightly server backups + daily desktop pull with a restricted key
- [x] English documentation: setup, migration, backups, history
- [x] Minecraft server live (Fabric 1.21.1, existing Hardcore world)
- [x] Desktop on LAN + `/etc/hosts` (Tailscale broke Discord voice there)
- [x] SSH hardened (keys only, no root); Termius on its own key
- [x] Git sync script (`scripts/stacks.sh`) + server deploy key
- [x] Existing Hardcore world restored (seed verified)
- [x] Portfolio live on https://rotten-guy.com (GitHub Pages, `CNAME`; apex A/AAAA + `www` CNAME at OVH)
- [x] Portfolio on https://rotten-guy.com (GitHub Pages)

## 🔜 Next

### Minecraft go-live
- [x] First boot of the pack (`Done` in 17 s, 57 s total)
- [x] Datapacks active (64, all mod-provided)
- [x] Existing Hardcore world restored
- [x] Overworld pre-generated (Chunky, radius 5000, centred on spawn -304,-112): 393 129 chunks in 29 h 32, world 5.3 GB
- [x] New backup settings applied (12 h / 3 days / zstd). Note: Dockge *Restart* doesn't apply compose changes; `docker compose up -d` in the stack folder (or *Deploy*) does
- [ ] Nether pre-generation (running, ~6 cps, ~1.5 h): `chunky world minecraft:the_nether` → `chunky center 0 0` → `chunky radius 1500` → `chunky start`
- [ ] End pre-generation: `chunky world minecraft:the_end` → `chunky center 0 0` → `chunky radius 2000` → `chunky start`
- [x] World backups land in `/opt/backups/minecraft` and reach the desktop
- [ ] Join in game from the client pack and confirm the mod list matches

### Security housekeeping
- [x] Harden SSH: no passwords, no root
- [ ] ⏸️ **Postponed (risk accepted)**: rotate the OVH API key (old one was exposed in screenshots; it can edit the DNS zone). NPM keeps DNS credentials in its database, not in a file, so rotating means:
  1. create a new key with the same rights;
  2. NPM: add a **new** wildcard certificate with the new key;
  3. switch every proxy host to the new certificate, check the old one shows *Not Used*, delete it;
  4. delete the old application in https://eu.api.ovh.com/console/ (*Authenticate* first, then `/me` section: `GET /me/api/application` → `GET …/{id}` to find `npm-rotten-server` → `DELETE …/{id}`).
- [ ] ~~old procedure (edit the credentials file)~~: does not work with NPM 2.16, the file only exists during renewals.
- [x] Server timezone Europe/Paris

### Git in sync with the server
- [x] `scripts/stacks.sh` (status / import / export of compose files)
- [x] Deploy key with write access on the server
- [x] First `export`: live files now match the repo
- [ ] Later, optionally: make `/opt/stacks` the Git working tree itself (Dockge pointed at the repo), which removes the import/export step

### Minecraft web tools (after pre-generation: adding mods restarts the server)
- [ ] **spark** (performance profiler): check if the pack already has it with `docker exec minecraft rcon-cli "spark tps"`; otherwise add it (`MODRINTH_PROJECTS: spark`)
- [ ] **Plan** (player analytics, web UI on port 8804): add the Fabric build, put `minecraft` on the `proxy` network, proxy host `stats.rotten-guy.com` → `minecraft:8804`

### BlueMap: `mcmap.rotten-guy.com`
Live 3D web map of the world.
- [ ] Add the BlueMap mod server-side: either in the pack, or via the itzg env `MODRINTH_PROJECTS: bluemap`. Must match the loader (Fabric / NeoForge) and MC version.
- [ ] Put the `minecraft` service on the `proxy` network (add `networks: [default, proxy]` + `external: true` declaration).
- [ ] Accept the download in `data/config/bluemap/core.conf` (`accept-download: true`), restart.
- [ ] NPM proxy host `mcmap.rotten-guy.com` → `minecraft:8100`, websockets on, wildcard cert.
- [ ] On the Celeron: limit the render radius and render after pre-generation, at night. Full renders are CPU-heavy.

## 💡 Later / ideas

### Reliability
- [ ] **Restore drill**: rebuild in a VM from the desktop backups using [MIGRATION.md](MIGRATION.md).
- [ ] **Off-site backup** (3-2-1 rule): encrypted `restic` copy of `/opt/backups` to cloud storage (Backblaze B2, a Hetzner Storage Box…).
- [ ] **Pin image versions** instead of `latest` (reproducible installs, updates on purpose), and use `diun` to get notified of new versions.
- [ ] **Monitoring**: Uptime Kuma (`status.rotten-guy.com`) + push notifications (ntfy) when a service or the server goes down.
- [ ] Secondary DNS fallback for the tailnet in case the server is down.
- [ ] Investigate Tailscale vs. Vesktop voice (DTLS) on Arch: `chrome://webrtc-internals`-style logs, Discord in the browser, another Electron client.

### Hardware
The Celeron G1840T is the bottleneck for modded Minecraft (single-thread performance + 6 GB RAM).

**Planned purchase (next payday), < 40 € total:**

| Part | Choice | Check on arrival | Effect |
|---|---|---|---|
| RAM | Samsung 2 × 8 GB DDR3L SO-DIMM, PC3L-12800S (M471B1G73EB0-YK0) | `PC3L`, 1600, SO-DIMM | 16 GB → `MC_MEMORY=8G`, room for Nextcloud |
| CPU | Intel i5-4590T (35 W, 4C/4T, 3.0 GHz turbo) | sSpec **SR1S6** | 2 → 4 cores, turbo |

Rejected: i7-4790 (84 W, too hot / too power-hungry for the Tiny's cooler and 65 W brick) and i7-4765T (+~35 € for Hyper-Threading only, on a platform that will be replaced anyway).
Thermal paste + isopropyl alcohol: already at home.

**Swap procedure:** wait for pre-generation to finish → `sudo systemctl poweroff` → swap CPU (clean + new paste) and both RAM sticks in one go → boot, check `fastfetch` / `free -h` → raise `MC_MEMORY`, view/simulation distance and `MAX_PLAYERS` (see [MIGRATION.md → hardware-specific values](MIGRATION.md#hardware-specific-values-to-revisit)).

### More services
- [ ] **Obsidian sync**: Syncthing (light, peer-to-peer, works on Android) or Obsidian LiveSync (CouchDB, real-time). Either fits in today's RAM.
- [ ] **Nextcloud** (files, calendar, contacts; can also host the Obsidian vault via WebDAV / Remotely Save): needs a database + Redis + PHP, ~1 GB RAM. Do it **after the 16 GB RAM upgrade**.
- [ ] Immich (photos), same constraint
- [ ] Portfolio self-hosted later (Cloudflare Tunnel) if GitHub Pages becomes limiting
