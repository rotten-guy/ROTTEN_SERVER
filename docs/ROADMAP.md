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

## 🔜 Next

### Minecraft go-live
- [x] First boot of the pack (`Done` in 17 s, 57 s total)
- [x] Datapacks active (64, all mod-provided)
- [x] Existing Hardcore world restored
- [ ] Pre-generation with Chunky (radius 2000) running: check `chunky progress`
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
- [ ] Deploy key with write access on the server ([SETUP § 12](SETUP.md#12-keep-git-in-sync))
- [ ] First `export` to replace the old French comments on the live files
- [ ] Later, optionally: make `/opt/stacks` the Git working tree itself (Dockge pointed at the repo), which removes the import/export step

### BlueMap: `mcmap.rotten-guy.com`
Live 3D web map of the world.
- [ ] Add the BlueMap mod server-side: either in the pack, or via the itzg env `MODRINTH_PROJECTS: bluemap`. Must match the loader (Fabric / NeoForge) and MC version.
- [ ] Put the `minecraft` service on the `proxy` network (add `networks: [default, proxy]` + `external: true` declaration).
- [ ] Accept the download in `data/config/bluemap/core.conf` (`accept-download: true`), restart.
- [ ] NPM proxy host `mcmap.rotten-guy.com` → `minecraft:8100`, websockets on, wildcard cert.
- [ ] On the Celeron: limit the render radius and render after pre-generation, at night. Full renders are CPU-heavy.

### Portfolio on `rotten-guy.com`
Public site, but the server stays private.
- [ ] Host on **GitHub Pages** with custom domain `rotten-guy.com`.
- [ ] OVH: remove OVH's parking records (`@` A `213.186.33.5`, `www` A `213.186.33.5`, `www` TXT `3|welcome`, `@` TXT `1|www…`); add `@` A ×4 `185.199.108–111.153` + `www` CNAME `rotten-guy.github.io.`. **Keep** the `*` record.
- [ ] Enforce HTTPS in GitHub Pages once the cert is issued.
- [ ] If the site needs a build step (Vite, Astro, React), add a Pages workflow in GitHub Actions.

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

| Upgrade | Part (used market) | Effect |
|---|---|---|
| RAM | 2 × 8 GB DDR3L SO-DIMM (16 GB max) | `MC_MEMORY=8G` |
| CPU | Intel i5-4590T or i7-4785T (LGA1150, 35 W) | 4 cores, >3 GHz turbo: much smoother ticks |

Both are drop-in for the M73 Tiny. After upgrading: raise `MC_MEMORY`, view and simulation distance (see [MIGRATION.md → hardware-specific values](MIGRATION.md#hardware-specific-values-to-revisit)).

### More services
- [ ] Portfolio self-hosted later (Cloudflare Tunnel) if GitHub Pages becomes limiting
- [ ] Nextcloud / Immich (photos) once storage and RAM allow
