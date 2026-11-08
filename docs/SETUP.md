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

## 9.5 Clients at home: LAN instead of Tailscale (optional)

A machine that never leaves home doesn't need Tailscale: point the names to the server's **LAN IP** instead. NPM listens on the LAN too, so HTTPS keeps working. This is how `rotten-desktop` is set up, because Tailscale broke Discord voice there.

```bash
sudo tailscale down && sudo systemctl disable --now tailscaled
```

```bash
printf '\n# rotten-server (LAN)\n192.168.1.107 rotten-server dockge.rotten-guy.com proxy.rotten-guy.com adguard.rotten-guy.com vault.rotten-guy.com mc.rotten-guy.com mcmap.rotten-guy.com\n' | sudo tee -a /etc/hosts
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

## Done checklist

- [ ] `docker ps` shows dockge, npm, adguard, vaultwarden, minecraft, minecraft-backup
- [ ] every `https://*.rotten-guy.com` URL loads with a valid certificate
- [ ] `nslookup doubleclick.net` → `0.0.0.0` on a client
- [ ] Vaultwarden sign-ups disabled
- [ ] `sudo /etc/cron.daily/homelab-backup` succeeds and the desktop pull works
- [ ] SSH password login refused
