# ROTTEN_SERVER — rotten-guy.com

```
rotten-server — ThinkCentre M73 Tiny (Debian 13)
├── Tailscale ............ VPN : accès de partout, aucun port ouvert sur la box
├── OpenSSH .............. clés uniquement (Termius)
└── Docker
    ├── dockge ........... interface web des stacks          :5001
    ├── proxy (NPM) ...... reverse proxy + HTTPS             :80 :443 (admin :81)
    ├── adguard .......... DNS + bloqueur de pubs            :53
    ├── vaultwarden ...... mots de passe   → https://vault.rotten-guy.com
    └── minecraft ........ itzg + mc-backup                  :25565
```

Tous les noms `*.rotten-guy.com` pointent vers l'**adresse Tailscale** du serveur (`100.x.y.z`) :
ils ne marchent que sur tes appareils connectés à Tailscale. Rien n'est exposé sur Internet.

```
ROTTEN_SERVER/
├── scripts/setup.sh                 # prépare le serveur et installe Dockge
├── scripts/backup.sh                # sauvegarde nocturne → /opt/backups (cron)
├── desktop/                         # récupération automatique des backups sur ton PC
├── dockge/compose.yaml              # → /opt/dockge
└── stacks/                          # → /opt/stacks (une stack = un dossier)
    ├── proxy/  adguard/  vaultwarden/  minecraft/
```

---

## 1. Préparer le serveur

Copie le dossier sur le serveur (SFTP de Termius, ou `scp -r ROTTEN_SERVER rotten-guy@192.168.1.107:~`), puis :

```bash
sudo apt update && sudo apt full-upgrade -y
```

```bash
cd ~/ROTTEN_SERVER && sudo bash scripts/setup.sh rotten-guy
```

Déconnecte-toi puis reconnecte-toi (pour le groupe `docker`). Vérifie que rien n'occupe déjà le port 53 :

```bash
sudo ss -tulpn | grep ':53 '
```

Si une ligne apparaît (`systemd-resolved`, `dnsmasq`…), dis-le-moi avant d'installer AdGuard.

## 2. Tailscale

```bash
sudo tailscale up --accept-dns=false
```

> `--accept-dns=false` : le serveur sera lui-même le DNS de ton réseau Tailscale ; il ne doit pas s'utiliser lui-même, sinon il perd Internet dès qu'AdGuard redémarre.

Dans la console Tailscale (login.tailscale.com) :
- vérifie que la machine s'appelle `rotten-server` et **désactive l'expiration de la clé** (`…` → *Disable key expiry*) ;
- note son adresse `100.x.y.z` :

```bash
tailscale ip -4
```

Installe Tailscale sur ton fixe, ton laptop et ton téléphone, avec le même compte.

### Durcir SSH (quand la connexion par clé Termius marche)

```bash
printf 'PasswordAuthentication no\nPermitRootLogin no\n' | sudo tee /etc/ssh/sshd_config.d/hardening.conf
```

```bash
sudo systemctl restart ssh
```

Garde ta session Termius ouverte et teste une **nouvelle** connexion avant de fermer l'ancienne.

## 3. DNS chez OVH

*Web Cloud → Noms de domaine → rotten-guy.com → Zone DNS → Ajouter une entrée* :

| Type | Sous-domaine | Cible |
|------|--------------|-------|
| A    | `*`          | `100.x.y.z` (IP Tailscale du serveur) |

Une seule entrée couvre `vault.`, `adguard.`, `dockge.`, `proxy.`, `mc.`… Supprime les entrées A/AAAA par défaut d'OVH qui pointeraient `www` ailleurs si tu ne t'en sers pas.

### Clé API OVH (pour les certificats HTTPS)

Les certificats Let's Encrypt sont validés par DNS (*DNS challenge*), car le serveur n'est pas joignable depuis Internet. Crée une clé sur **https://eu.api.ovh.com/createToken/** :
- Validity : *Unlimited*
- Rights : `GET`, `POST`, `PUT`, `DELETE` sur `/domain/zone/rotten-guy.com/*`, et `GET` sur `/domain/zone/*`

Garde les trois valeurs (Application Key, Application Secret, Consumer Key).

## 4. Déployer les stacks dans Dockge

Ouvre `http://192.168.1.107:5001`, crée ton compte. Les 4 stacks y apparaissent déjà. Déploie-les **dans cet ordre** :

### 4.1 proxy (Nginx Proxy Manager)

1. *Deploy*, puis ouvre `http://192.168.1.107:81` et crée ton compte admin.
2. **SSL Certificates → Add → Let's Encrypt** :
   - Domain names : `rotten-guy.com` et `*.rotten-guy.com`
   - *Use a DNS Challenge* → **OVH**, remplace le contenu par :
     ```
     dns_ovh_endpoint = ovh-eu
     dns_ovh_application_key = ...
     dns_ovh_application_secret = ...
     dns_ovh_consumer_key = ...
     ```
   - Propagation seconds : `120`
3. Chaque service = un **Proxy Host** avec ce certificat wildcard, *Force SSL* coché :

| Domaine | Forward host | Port | Websockets |
|---------|--------------|------|------------|
| `proxy.rotten-guy.com`   | `npm`         | 81   | |
| `dockge.rotten-guy.com`  | `dockge`      | 5001 | ✅ |
| `adguard.rotten-guy.com` | `adguard`     | 3000 | |
| `vault.rotten-guy.com`   | `vaultwarden` | 80   | ✅ |

Les noms de conteneurs marchent car tout est sur le réseau Docker `proxy`.

### 4.2 adguard

1. *Deploy*, puis assistant sur `http://192.168.1.107:3000`.
2. **Interface web : port 3000** (pas 80, il est pris par le proxy). **DNS : port 53**.
3. Ajoute le Proxy Host `adguard.rotten-guy.com` (tableau ci-dessus).
4. Pour que tous tes appareils l'utilisent, dans la console Tailscale → **DNS** → *Add nameserver → Custom* → `100.x.y.z`, puis active **Override local DNS**.
5. *(Optionnel)* Pour le réseau de la maison sans Tailscale : dans la box, mets l'IP locale du serveur comme DNS du DHCP.

> Si le serveur tombe, les appareils qui l'utilisent comme DNS n'ont plus de résolution. En cas de pépin : désactive Tailscale sur l'appareil, ou repasse la box en DNS automatique.

### 4.3 vaultwarden

1. Dans Dockge, onglet `.env` de la stack : `SIGNUPS_ALLOWED=true`, puis *Deploy*.
2. Ajoute le Proxy Host `vault.rotten-guy.com`.
3. Va sur `https://vault.rotten-guy.com`, crée ton compte. **Le mot de passe maître est irrécupérable.**
4. Remets `SIGNUPS_ALLOWED=false` et redéploie.
5. Sur tes appareils : appli/extension **Bitwarden** → *Auto-hébergé* → `https://vault.rotten-guy.com`.

Sauvegardé chaque nuit avec le reste : voir [Sauvegardes](#sauvegardes).

### 4.4 minecraft

1. Copie ton pack dans `/opt/stacks/minecraft/modpacks/pack.mrpack`.
2. Onglet `.env` (modèle dans `.env.example`) : `MC_MEMORY`, `MC_WHITELIST`, `MC_OPS`, `RCON_PASSWORD`.
3. *Deploy* et suis les logs jusqu'à `Done (…)!`.
4. Dans Minecraft : adresse **`mc.rotten-guy.com`**.

### Performances sur ce matériel (Celeron G1840T, 2 cœurs, 5,7 Go)

C'est la limite de la machine : le reste des services consomme peu, mais un gros modpack est exigeant.

- `MC_MEMORY=3G` maximum (le système + les autres services prennent ~1,5 Go).
- `VIEW_DISTANCE: 8` et `SIMULATION_DISTANCE: 6` (déjà réglés).
- **Pré-génère le monde** avant d'y jouer, c'est la génération de chunks qui fait ramer un petit CPU. Si le pack contient le mod *Chunky* (sinon ajoute-le côté serveur) :

```bash
docker exec minecraft rcon-cli "chunky radius 2000"
```

```bash
docker exec minecraft rcon-cli "chunky start"
```

Laisse tourner une nuit. Vérifie aussi que le pack contient des mods d'optimisation serveur : *Lithium*, *FerriteCore*, *ModernFix*.

**Upgrades conseillés (pas chers, en occasion)** : la M73 Tiny accepte jusqu'à 16 Go de DDR3L SO-DIMM (2 barrettes) et un CPU LGA1150 35 W comme l'**i5-4590T** ou l'**i7-4785T** (4 cœurs, turbo > 3 GHz). Avec 16 Go → `MC_MEMORY=8G`.

Commandes utiles :

| Action | Commande |
|--------|----------|
| Console du serveur | `docker exec -it minecraft rcon-cli` |
| Backup immédiat | `docker exec minecraft-backup backup now` |
| Mettre à jour le pack | backup, remplacer `pack.mrpack`, *Recreate* dans Dockge |

Restaurer un monde : arrêter la stack, `mv data/world data/world.old`, `tar -xzf /opt/backups/minecraft/<archive>.tgz -C data`, relancer.

---

## Sauvegardes

```
rotten-server                                   rotten-desktop
/opt/backups/                                   ~/backups/rotten-server/
├── vaultwarden/  ← chaque nuit (cron)   ──►    copie quotidienne (timer systemd)
├── config/       ← chaque nuit (cron)          gardée 90 jours, jamais effacée
└── minecraft/    ← toutes les 6 h (mc-backup)  si le serveur est vidé
     gardé 30 jours (Minecraft : 7)
```

`config/` contient toutes les stacks : proxy + certificats, AdGuard, Dockge, et les `.env`.
**Ces archives contiennent des secrets** : elles ne sont lisibles que par `rotten-guy`.

### Sur le serveur

```bash
cd ~/ROTTEN_SERVER && git pull
```

```bash
sudo apt install -y rsync && sudo rm -f /etc/cron.daily/backup-vaultwarden
```

```bash
sudo install -m 755 scripts/backup.sh /etc/cron.daily/homelab-backup
```

Test :

```bash
sudo /etc/cron.daily/homelab-backup && ls -lhR /opt/backups
```

### Sur ton PC (Arch)

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

Test immédiat, puis vérification :

```bash
systemctl --user start rotten-backup.service && journalctl --user -u rotten-backup -n 20
```

```bash
ls -lhR ~/backups/rotten-server
```

#### Clé SSH dédiée (une seule fois)

Le service tourne en arrière-plan : il ne peut pas taper la phrase de passe de ta clé principale. On lui donne une clé à lui, **sans phrase de passe mais bridée** : elle ne peut que *lire* `/opt/backups` (pas de shell, pas d'écriture).

```bash
ssh-keygen -t ed25519 -N "" -C "backup@rotten-desktop" -f ~/.ssh/rotten_backup
```

```bash
echo "command=\"/usr/bin/rrsync -ro /opt/backups/\",restrict $(cat ~/.ssh/rotten_backup.pub)" | ssh rotten-guy@rotten-server 'cat >> ~/.ssh/authorized_keys'
```

Vérification : cette commande doit être **refusée** (la clé ne permet pas d'ouvrir un shell) :

```bash
ssh -i ~/.ssh/rotten_backup -o IdentitiesOnly=yes rotten-guy@rotten-server
```

`Persistent=true` : si ton PC est éteint à midi, la copie se fait au prochain démarrage.

### Restaurer

| Quoi | Comment |
|---|---|
| Vaultwarden | Arrêter la stack, vider `/opt/stacks/vaultwarden/data`, `sudo tar -xzf vaultwarden-<date>.tgz -C /opt/stacks/vaultwarden/data`. Si un fichier `db_*.sqlite3` est présent, le renommer en `db.sqlite3`. Relancer. |
| Configs | `sudo tar -xzf config-<date>.tgz -C /opt` (restaure `/opt/stacks` et `/opt/dockge`) |
| Monde Minecraft | voir la section Minecraft |

**En plus**, exporte ton coffre de temps en temps depuis le coffre web (*Outils → Exporter*, format **chiffré**), et range le fichier ailleurs. C'est ta roue de secours si tout le reste échoue.

## Sécurité, en résumé

- Aucun port redirigé sur la box. Tant que c'est le cas, rien n'est joignable depuis Internet.
- SSH par clé uniquement.
- Mises à jour de sécurité Debian automatiques. Pour les conteneurs : *Update* dans Dockge de temps en temps (sauvegarde avant pour Minecraft et Vaultwarden).
