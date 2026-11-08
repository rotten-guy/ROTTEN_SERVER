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

## 🔜 Next

### Minecraft go-live
- [ ] First boot of the pack, wait for `Done (…)!`
- [ ] Check datapacks are active: `docker exec minecraft rcon-cli "datapack list"`. Datapacks shipped in the `.mrpack` land in `/data/datapacks`, which vanilla doesn't load unless the pack has a global-datapack mod (Paxi, Open Loader…). If missing, copy them into `data/world/datapacks/`.
- [ ] Verify the client pack matches the server pack (same mod versions), or joining fails.
- [ ] Pre-generate the world with Chunky (radius 2000, overnight).
- [ ] Confirm `/opt/backups/minecraft` fills up and reaches the desktop.

### Security housekeeping
- [ ] Harden SSH: no passwords, no root ([SETUP § 11](SETUP.md#11-harden-ssh))
- [ ] Rotate the OVH API key (old one was exposed in screenshots):
  1. create a new key with the same rights;
  2. replace the 3 values in `/opt/stacks/proxy/letsencrypt/credentials/credentials-1`;
  3. delete the old application via https://eu.api.ovh.com/console/ (`GET /me/api/application` → `DELETE /me/api/application/{id}`);
  4. NPM → Certificates → ⋮ → **Renew Now** to prove the new key works.
- [ ] `sudo timedatectl set-timezone Europe/Paris` on the current server (new installs get it from `setup.sh`)

### Make Git the source of truth
Today `/opt/stacks` is a *copy* of the repo, so edits made in Dockge don't flow back to GitHub (drift).
- [ ] Turn `/opt/stacks` into the repo's working tree, e.g. move the clone to `/opt/ROTTEN_SERVER` and point Dockge's `DOCKGE_STACKS_DIR` at `/opt/ROTTEN_SERVER/stacks`. `.gitignore` already excludes data and secrets.
- [ ] Then every Dockge edit shows up in `git diff`; commit + push from the server.

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
