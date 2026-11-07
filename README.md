# Homelab NUC — rotten-guy.com

```
NUC (Debian 13)
├── Tailscale ............ VPN : accès de partout, aucun port ouvert sur la box
├── OpenSSH .............. clés uniquement (Termius)
└── Docker
    ├── dockge ........... interface web des stacks          :5001
    ├── proxy (NPM) ...... reverse proxy + HTTPS             :80 :443 (admin :81)
    ├── adguard .......... DNS + bloqueur de pubs            :53
    ├── vaultwarden ...... mots de passe   → https://vault.rotten-guy.com
    └── minecraft ........ itzg + mc-backup                  :25565
```

Tous les noms `*.rotten-guy.com` pointent vers l'**adresse Tailscale** du NUC (`100.x.y.z`) :
ils ne marchent que sur tes appareils connectés à Tailscale. Rien n'est exposé sur Internet.

```
homelab/
├── scripts/setup.sh                 # prépare le NUC et installe Dockge
├── scripts/backup-vaultwarden.sh    # sauvegarde quotidienne (cron)
├── dockge/compose.yaml              # → /opt/dockge
└── stacks/                          # → /opt/stacks (une stack = un dossier)
    ├── proxy/  adguard/  vaultwarden/  minecraft/
```

---

## 1. Préparer le NUC

Copie le dossier sur le NUC (SFTP de Termius, ou `scp -r homelab rotten_guy@<ip>:~`), puis :

```bash
sudo apt update && sudo apt full-upgrade -y
```

```bash
cd ~/homelab && sudo bash scripts/setup.sh rotten_guy
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

> `--accept-dns=false` : le NUC sera lui-même le DNS de ton réseau Tailscale ; il ne doit pas s'utiliser lui-même, sinon il perd Internet dès qu'AdGuard redémarre.

Dans la console Tailscale (login.tailscale.com) :
- renomme la machine en `nuc` et **désactive l'expiration de la clé** (`…` → *Disable key expiry*) ;
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
| A    | `*`          | `100.x.y.z` (IP Tailscale du NUC) |

Une seule entrée couvre `vault.`, `adguard.`, `dockge.`, `proxy.`, `mc.`… Supprime les entrées A/AAAA par défaut d'OVH qui pointeraient `www` ailleurs si tu ne t'en sers pas.

### Clé API OVH (pour les certificats HTTPS)

Les certificats Let's Encrypt sont validés par DNS (*DNS challenge*), car le serveur n'est pas joignable depuis Internet. Crée une clé sur **https://eu.api.ovh.com/createToken/** :
- Validity : *Unlimited*
- Rights : `GET`, `POST`, `PUT`, `DELETE` sur `/domain/zone/rotten-guy.com/*`, et `GET` sur `/domain/zone/*`

Garde les trois valeurs (Application Key, Application Secret, Consumer Key).

## 4. Déployer les stacks dans Dockge

Ouvre `http://<ip-du-nuc>:5001`, crée ton compte. Les 4 stacks y apparaissent déjà. Déploie-les **dans cet ordre** :

### 4.1 proxy (Nginx Proxy Manager)

1. *Deploy*, puis ouvre `http://<ip-du-nuc>:81` et crée ton compte admin.
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

1. *Deploy*, puis assistant sur `http://<ip-du-nuc>:3000`.
2. **Interface web : port 3000** (pas 80, il est pris par le proxy). **DNS : port 53**.
3. Ajoute le Proxy Host `adguard.rotten-guy.com` (tableau ci-dessus).
4. Pour que tous tes appareils l'utilisent, dans la console Tailscale → **DNS** → *Add nameserver → Custom* → `100.x.y.z`, puis active **Override local DNS**.
5. *(Optionnel)* Pour le réseau de la maison sans Tailscale : dans la box, mets l'IP locale du NUC comme DNS du DHCP.

> Si le NUC tombe, les appareils qui l'utilisent comme DNS n'ont plus de résolution. En cas de pépin : désactive Tailscale sur l'appareil, ou repasse la box en DNS automatique.

### 4.3 vaultwarden

1. Dans Dockge, onglet `.env` de la stack : `SIGNUPS_ALLOWED=true`, puis *Deploy*.
2. Ajoute le Proxy Host `vault.rotten-guy.com`.
3. Va sur `https://vault.rotten-guy.com`, crée ton compte. **Le mot de passe maître est irrécupérable.**
4. Remets `SIGNUPS_ALLOWED=false` et redéploie.
5. Sur tes appareils : appli/extension **Bitwarden** → *Auto-hébergé* → `https://vault.rotten-guy.com`.

Sauvegarde automatique chaque nuit dans `/opt/backups/vaultwarden/` (30 jours). Test manuel :

```bash
sudo /etc/cron.daily/backup-vaultwarden && ls -lh /opt/backups/vaultwarden
```

### 4.4 minecraft

1. Copie ton pack dans `/opt/stacks/minecraft/modpacks/pack.mrpack`.
2. Onglet `.env` (modèle dans `.env.example`) : `MC_MEMORY`, `MC_WHITELIST`, `MC_OPS`, `RCON_PASSWORD`.
3. *Deploy* et suis les logs jusqu'à `Done (…)!`.
4. Dans Minecraft : adresse **`mc.rotten-guy.com`**.

| RAM du NUC | `MC_MEMORY` (avec les autres services) |
|------------|-------------|
| 8 Go       | `4G`        |
| 16 Go      | `8G`        |
| 32 Go      | `10G`       |

Commandes utiles :

| Action | Commande |
|--------|----------|
| Console du serveur | `docker exec -it minecraft rcon-cli` |
| Backup immédiat | `docker exec minecraft-backup backup now` |
| Mettre à jour le pack | backup, remplacer `pack.mrpack`, *Recreate* dans Dockge |

Restaurer un monde : arrêter la stack, `mv data/world data/world.old`, `tar -xzf backups/<archive>.tgz -C data`, relancer.

---

## Sauvegardes hors du NUC (à faire !)

Les sauvegardes sont sur le même SSD que tout le reste. Copie-les régulièrement ailleurs, par exemple depuis ton fixe :

```bash
rsync -av rotten_guy@nuc:/opt/backups/ ~/backups-nuc/
```

```bash
rsync -av rotten_guy@nuc:/opt/stacks/minecraft/backups/ ~/backups-nuc/minecraft/
```

Pour Vaultwarden en particulier : exporte aussi ton coffre de temps en temps (*Outils → Exporter* dans le coffre web), au format chiffré.

## Sécurité, en résumé

- Aucun port redirigé sur la box. Tant que c'est le cas, rien n'est joignable depuis Internet.
- SSH par clé uniquement.
- Mises à jour de sécurité Debian automatiques. Pour les conteneurs : *Update* dans Dockge de temps en temps (sauvegarde avant pour Minecraft et Vaultwarden).
