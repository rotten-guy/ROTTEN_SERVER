# Setup from scratch

Build a new `rotten-server` from bare metal. Moving an **existing** install to new hardware? Follow [MIGRATION.md](MIGRATION.md) instead; it reuses most of this page.

Time: ~2 hours, most of it waiting for downloads.

## 0. Prerequisites

| Need | Where |
|---|---|
| A domain whose DNS is managed at OVH | `rotten-guy.com` |
| A Tailscale account | login.tailscale.com (GitHub login) |
| An SSH key on your desktop / in Termius | `ssh-keygen -t ed25519` |
| A Debian 13 `netinst` USB stick | debian.org |

## 1. BIOS

- **After Power Failure → Power On**, so the server comes back by itself after a power cut.
- Disable what's unused (Wi-Fi, Bluetooth, card reader).
- Use **Ethernet**.

## 2. Install Debian 13

- Software selection: **only** "SSH server" + "standard system utilities". No desktop.
- Hostname: `rotten-server`. User: `rotten-guy`.
- Give the user sudo rights, then **log out completely and back in**. Group changes only apply to new sessions; a reboot is the surest way.

```bash
su -c "/usr/sbin/usermod -aG sudo rotten-guy"
```

> Gotcha: plain `su` keeps the user's `PATH` (no `/usr/sbin`), so `reboot` is "not found". Use `su -` or `systemctl reboot`.

## 3. Router

On the Bbox, give the server a **static DHCP lease** (find it in the device list once it's connected).
**Do not forward any port.**

## 4. SSH keys

From the desktop (and/or Termius → *Keychain → Generate key* → *Export to host*):

```bash
ssh-copy-id rotten-guy@<server-lan-ip>
```

Hardening comes at the end of this guide, once keys are proven to work.

## 5. Bootstrap

```bash
sudo apt update && sudo apt full-upgrade -y && sudo apt install -y git
```

```bash
git clone https://github.com/rotten-guy/ROTTEN_SERVER.git ~/ROTTEN_SERVER
```

```bash
cd ~/ROTTEN_SERVER && sudo bash scripts/setup.sh rotten-guy
```

`setup.sh` installs Docker, Tailscale, ufw, unattended-upgrades and powertop, sets the timezone, creates the `proxy` Docker network, copies the stacks to `/opt/stacks`, installs the nightly backup and starts Dockge.

Log out and back in (for the `docker` group), then check:

```bash
docker ps
```

```bash
sudo ss -tulpn | grep ':53 '
```

`dockge` must be *Up*, and port 53 must be free (no output from the second command).

> If the network drops randomly afterwards, powertop's NIC power saving is the usual suspect: `sudo systemctl disable powertop.service` and reboot.

## 6. Tailscale

```bash
sudo tailscale up --accept-dns=false
```

Open the link, log in, click **Connect**, and don't Ctrl+C before it prints `Success.`.
`--accept-dns=false` matters: this server *is* the tailnet's DNS (AdGuard), and it must not depend on itself.

In the admin console (login.tailscale.com/admin/machines):
- machine name `rotten-server` → `…` → **Disable key expiry**;
- note its IP:

```bash
tailscale ip -4
```

Install Tailscale on every client (desktop, laptop, phone), using the same account. On Android, enable **Always-on VPN** for Tailscale.

## 7. DNS at OVH

*Web Cloud → Domain names → rotten-guy.com → DNS zone → Add an entry → A*:

| Subdomain | Target |
|---|---|
| `*` | `<Tailscale IP>` |

Check from a client: `ping test.rotten-guy.com` must answer from the Tailscale IP.

The apex and `www` are **not** covered by the wildcard: they serve the public portfolio on GitHub Pages (`@` A ×4 `185.199.108–111.153`, `@` AAAA ×4 `2606:50c0:8000–8003::153`, `www` CNAME `rotten-guy.github.io.`). Delete OVH's default parking records (`213.186.33.5`, `3|welcome`, `1|www…`).

## 8. OVH API key (for HTTPS certificates)

The server is not reachable from the Internet, so Let's Encrypt validates through DNS (DNS-01 challenge). Create a key at **https://eu.api.ovh.com/createToken/**:

- Validity: *Unlimited*
- Rights:

| Method | Path |
|---|---|
| GET | `/domain/zone/*` |
| GET | `/domain/zone/rotten-guy.com/*` |
| POST | `/domain/zone/rotten-guy.com/*` |
| PUT | `/domain/zone/rotten-guy.com/*` |
| DELETE | `/domain/zone/rotten-guy.com/*` |

Store the 3 values in Vaultwarden (once it exists) and **never screenshot them**.

## 9. Stacks: deploy in this order

Open Dockge at `http://rotten-server:5001` and create the admin account. The stacks are already listed.

### 9.1 proxy: Nginx Proxy Manager

1. **Deploy**, open `http://rotten-server:81`, create the admin account.
2. **Certificates → Add Certificate → Let's Encrypt via DNS**:
   - Domain names: `rotten-guy.com`, `*.rotten-guy.com`
   - Key type: ECDSA 256
   - DNS provider: **OVH**; credentials:
     ```
     dns_ovh_endpoint = ovh-eu
     dns_ovh_application_key = ...
     dns_ovh_application_secret = ...
     dns_ovh_consumer_key = ...
     ```
   - Propagation seconds: `120`
   The first run installs the certbot OVH plugin, so allow 3 to 5 minutes. Follow it with `docker logs -f npm`.
3. **Hosts → Proxy Hosts**. Each one uses the wildcard cert with *Force SSL* + *HTTP/2* and *Block Common Exploits*:

| Domain | Forward host | Port | Websockets |
|---|---|---|---|
| `dockge.rotten-guy.com` | `dockge` | 5001 | ✅ |
| `proxy.rotten-guy.com` | `npm` | 81 | |
| `adguard.rotten-guy.com` | `adguard` | 3000 | |
| `vault.rotten-guy.com` | `vaultwarden` | 80 | ✅ |

Container names resolve because everything shares the `proxy` Docker network.

### 9.2 adguard

1. **Deploy**, then run the wizard at `http://rotten-server:3000`.
2. Admin web interface: **port 3000** (80 is taken by the proxy). DNS server: **port 53**. All interfaces.
3. Add the `adguard.rotten-guy.com` proxy host.
4. Tailscale admin → **DNS → Global nameservers → Add nameserver → Custom** → `<Tailscale IP>`, enable **Override DNS servers**, keep MagicDNS on.
5. Test from a client: `nslookup doubleclick.net` must return `0.0.0.0`.

### 9.3 vaultwarden

1. Stack `.env`: `SIGNUPS_ALLOWED=true` → **Deploy** (not just *Save*).
2. Add the `vault.rotten-guy.com` proxy host.
3. Create your account at https://vault.rotten-guy.com. **The master password cannot be recovered.**
4. `.env`: `SIGNUPS_ALLOWED=false` → **Deploy**. Check that sign-up now fails in a private window.
5. Clients: Bitwarden app / extension → *Logging in on: self-hosted* → `https://vault.rotten-guy.com`. They need Tailscale up to sync; the vault stays readable offline.

### 9.4 minecraft

1. Copy the server pack. SFTP can't write to `/opt`, so go through your home folder:
   ```bash
   scp my-pack.mrpack rotten-guy@rotten-server:~/pack.mrpack
   ```
   ```bash
   sudo mkdir -p /opt/stacks/minecraft/modpacks && sudo mv ~/pack.mrpack /opt/stacks/minecraft/modpacks/pack.mrpack
   ```
2. Check the pack's Minecraft version: 1.20.5 → 1.21.x keeps `java21`; 26.x needs `java25` in the `image:` tag.
3. Stack `.env` (template in `.env.example`): `MC_MEMORY`, `MC_WHITELIST`, `MC_OPS`, `RCON_PASSWORD`.
4. **Deploy** and follow the logs until `Done (…)! For help, type "help"`. The first boot downloads the loader + every mod: 10+ minutes on the Celeron.
5. In game: **`mc.rotten-guy.com`**.
6. Pre-generate the world so players don't pay the chunk-generation cost (requires the Chunky mod):
   ```bash
   docker exec minecraft rcon-cli "chunky radius 2000"
   ```
   ```bash
   docker exec minecraft rcon-cli "chunky start"
   ```

Performance notes for the current hardware:
- `MC_MEMORY=3G` max: the OS and the other stacks need ~1.5 GB.
- View distance 8 and simulation distance 6 are already set.
- Server-side optimisation mods help a lot: Lithium, FerriteCore, ModernFix.

### 9.5 files (FileBrowser)

FileBrowser runs as UID 1000 like the Minecraft container, so its data folders must exist with that owner **before** the first deploy:

```bash
sudo mkdir -p /opt/stacks/files/data/database /opt/stacks/files/data/config && sudo chown -R 1000:1000 /opt/stacks/files/data
```

1. **Deploy**, then read the first-login password in the logs (`User 'admin' initialized with randomly generated password: …`) and the listening port (`Listening on …:80`).
2. Proxy host `files.rotten-guy.com` → `filebrowser`, that port, wildcard cert.
3. Log in as `admin`, **change the password** (*Settings → Profile*).
4. Only `/opt/stacks/minecraft/data` is exposed. After editing a mod config, restart the minecraft stack.

### 9.6 homepage (dashboard)

1. Stack `.env` (template in `.env.example`): AdGuard and NPM logins for the widgets.
2. **Deploy**, proxy host `home.rotten-guy.com` → `homepage:3000`, wildcard cert.
3. The dashboard is `stacks/homepage/config/*.yaml`, versioned in Git and synced by `scripts/stacks.sh`. Homepage reloads changes by itself.

### 9.7 minecraft-return (background pre-generation)

A second server with the **same pack and settings** and a **random seed**: the future "official" Hardcore world. It never runs at the same time as `minecraft` (6 GB of RAM): the `mc` command switches between them, and a timer chains Chunky over the 3 dimensions (Overworld 5000 around spawn, Nether 1500, End 2000).

Once (already done by `setup.sh` on a new install):

```bash
sudo ln -sf ~/ROTTEN_SERVER/scripts/mc.sh /usr/local/bin/mc
```

```bash
sudo install -m 644 ~/ROTTEN_SERVER/systemd/mc-pregen.{service,timer} /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now mc-pregen.timer
```

Prepare the world (copies the practice server's mod configs, world datapacks, `serverconfig/` and `.env` **before** the world is created):

```bash
mc init-return
```

Then, every time you stop playing:

```bash
mc pregen
```

and when you want to play again:

```bash
mc play
```

`mc status` shows the mode, the players online, Chunky's progress and the plan; `mc seed` gives the new world's seed. Progress is kept across switches: Chunky saves on every graceful stop and `mc tick` resumes it.

#### Pre-generating on a faster machine (e.g. the desktop)

Generation is deterministic (same seed + same mods + same configs + same datapacks ⇒ same world), so any machine can do it. The desktop (i7-9700K) is several times faster than the Celeron.

1. Server: `mc stop` (or `mc play`), then package the stack **with its mods and the pack**:
   ```bash
   sudo tar -C /opt/stacks -czf ~/mc-return.tgz minecraft-return minecraft/modpacks/pack.mrpack && sudo chown rotten-guy: ~/mc-return.tgz
   ```
   ⚠️ Don't `mc pregen` on the server while the other machine generates: the two copies would diverge.
2. Desktop (Arch): Docker, then unpack next to each other:
   ```bash
   sudo pacman -S --needed docker docker-compose && sudo systemctl enable --now docker
   ```
   ```bash
   mkdir -p ~/mc-pregen && sudo tar -xzf ~/mc-return.tgz -C ~/mc-pregen && sudo chown -R 1000:1000 ~/mc-pregen
   ```
3. Point the pack mount to the local copy and give it more RAM. The override file in `~/mc-pregen/minecraft-return/compose.override.yaml`:
   ```yaml
   services:
     mc:
       volumes:
         - ../minecraft/modpacks:/modpacks:ro
   ```
   and `MC_MEMORY=10G` in its `.env`.
4. Run the same script against that folder:
   ```bash
   MC_RET_DIR=~/mc-pregen/minecraft-return ~/ROTTEN_SERVER/scripts/mc.sh pregen
   ```
   ```bash
   MC_RET_DIR=~/mc-pregen/minecraft-return ~/ROTTEN_SERVER/scripts/mc.sh loop
   ```
5. When the loop says *Plan complete*: `… mc.sh stop`, then send `minecraft-return/` back and swap it in on the server (old copy kept aside, `chown -R 1000:1000`, `pregen-step` already at 4).

## 9.8 Clients at home: LAN instead of Tailscale (optional)

A machine that never leaves home doesn't need Tailscale: point the names to the server's **LAN IP** instead. NPM listens on the LAN too, so HTTPS keeps working. This is how `rotten-desktop` is set up, because Tailscale broke Discord voice there.

```bash
sudo tailscale down && sudo systemctl disable --now tailscaled
```

```bash
printf '\n# rotten-server (LAN)\n192.168.1.107 rotten-server home.rotten-guy.com dockge.rotten-guy.com proxy.rotten-guy.com adguard.rotten-guy.com vault.rotten-guy.com files.rotten-guy.com stats.rotten-guy.com mc.rotten-guy.com mcmap.rotten-guy.com\n' | sudo tee -a /etc/hosts
```

```bash
ping -c1 vault.rotten-guy.com
```

The ping must answer from `192.168.1.107`. Add every new subdomain to that `/etc/hosts` line. For ad blocking on such a machine, set its DNS server to `192.168.1.107` (AdGuard answers on the LAN).

## 10. Backups

Follow [BACKUPS.md](BACKUPS.md): server side (already installed by `setup.sh`) + desktop pull with the restricted key.

## 11. Harden SSH

Only once key login works from **every** client (desktop, Termius). Keep a session open while doing this.

```bash
printf 'PasswordAuthentication no\nPermitRootLogin no\nKbdInteractiveAuthentication no\n' | sudo tee /etc/ssh/sshd_config.d/hardening.conf
```

```bash
sudo sshd -t && sudo systemctl restart ssh
```

From another terminal, a normal login must work and a password-only login must be refused:

```bash
ssh rotten-guy@rotten-server
```

```bash
ssh -o PubkeyAuthentication=no rotten-guy@rotten-server
```

## 12. Keep Git in sync

`/opt/stacks` is the live copy that Dockge edits; the repo is the reference. `scripts/stacks.sh` moves **compose files only** between them (never `.env`, never data):

| Command | Direction | When |
|---|---|---|
| `scripts/stacks.sh status` | compare | anytime: shows a diff |
| `scripts/stacks.sh import` | live → repo | after editing a stack in Dockge, then commit + push |
| `scripts/stacks.sh export` | repo → live | after `git pull`, then *Deploy* the changed stacks |

### Push access from the server (once)

A **deploy key** gives this server write access to this repo only.

```bash
ssh-keygen -t ed25519 -N "" -C "rotten-server deploy key" -f ~/.ssh/github_rotten_server
```

```bash
cat ~/.ssh/github_rotten_server.pub
```

GitHub → repo → *Settings → Deploy keys → Add deploy key* → paste it, tick **Allow write access**.

```bash
printf 'Host github.com\n  IdentityFile ~/.ssh/github_rotten_server\n  IdentitiesOnly yes\n' >> ~/.ssh/config && chmod 600 ~/.ssh/config
```

```bash
ssh -T git@github.com
```

The answer must contain `successfully authenticated`.

```bash
cd ~/ROTTEN_SERVER && git remote set-url origin git@github.com:rotten-guy/ROTTEN_SERVER.git
```

```bash
git config user.name "rotten-server" && git config user.email "<your GitHub email or noreply address>"
```

## Done checklist

- [ ] `docker ps` shows dockge, npm, adguard, vaultwarden, minecraft, minecraft-backup
- [ ] every `https://*.rotten-guy.com` URL loads with a valid certificate
- [ ] `nslookup doubleclick.net` → `0.0.0.0` on a client
- [ ] Vaultwarden sign-ups disabled
- [ ] `sudo /etc/cron.daily/homelab-backup` succeeds and the desktop pull works
- [ ] SSH password login refused
