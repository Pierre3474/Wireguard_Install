# Installation de WireGuard dans un conteneur LXC Proxmox

Script Bash qui installe et configure un serveur VPN WireGuard dans un conteneur LXC Debian 12, sur Proxmox VE. Il pose les questions nécessaires, crée un premier client et laisse un second script pour en ajouter d'autres.

## Ce que fait le script

`setup-wireguard.sh`, lancé en root dans le conteneur :

1. vérifie que `/dev/net/tun` est disponible ;
2. installe `wireguard`, `iptables`, `iproute2`, `qrencode`, `openresolv`, `curl` et `net-tools` ;
3. demande l'interface de sortie, l'adresse publique ou le nom de domaine du serveur, l'adresse du serveur dans le VPN, le port et les serveurs DNS ;
4. active le routage IPv4 (`/etc/sysctl.d/wg.conf`) ;
5. génère les clés du serveur et écrit `/etc/wireguard/wg0.conf`, avec les règles `iptables` de NAT en `PostUp` et `PostDown` ;
6. active et démarre le service `wg-quick@wg0` ;
7. crée un premier client et affiche son QR code ;
8. écrit `/root/add-client.sh` pour ajouter les clients suivants.

Valeurs par défaut :

| Réglage | Valeur |
|---|---|
| Adresse du serveur dans le VPN | `10.66.66.1/24` |
| Port | `51820/udp` |
| DNS donné aux clients | `1.1.1.1` |
| Trafic envoyé dans le tunnel par les clients | tout (`0.0.0.0/0, ::/0`) |

## Prérequis

- Proxmox VE et un conteneur LXC Debian 12.
- Le périphérique TUN dans le conteneur (voir ci-dessous).
- Une redirection du port UDP choisi depuis la box vers le conteneur.

### Donner le périphérique TUN au conteneur

Sur l'hôte Proxmox, conteneur arrêté, ajouter à `/etc/pve/lxc/<ID>.conf` :

```
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```

Puis démarrer le conteneur. Sans ces deux lignes, le script s'arrête à la première vérification.

## Installation

Dans le conteneur, en root :

```bash
apt update && apt install -y git
git clone https://github.com/Pierre3474/Wireguard_Install.git
cd Wireguard_Install
chmod +x setup-wireguard.sh
./setup-wireguard.sh
```

Le script affiche un récapitulatif et demande une confirmation avant de modifier le système.

## Ajouter un client

```bash
/root/add-client.sh
```

Le script demande un nom, attribue l'adresse libre suivante, génère les clés et ajoute le client au serveur. La configuration est écrite dans `/etc/wireguard/clients/<nom>/<nom>.conf` et affichée en QR code pour l'application mobile.

Sur un ordinateur, importer le fichier `.conf` dans le client WireGuard.

## Vérifier

```bash
systemctl status wg-quick@wg0   # état du service
wg show                         # interface, clients, dernière poignée de main
```

Si un client se connecte sans accès à Internet, vérifier la redirection de port sur la box, puis le routage : `sysctl net.ipv4.ip_forward` doit renvoyer `1`.

## Fichiers créés

| Chemin | Contenu |
|---|---|
| `/etc/wireguard/wg0.conf` | configuration du serveur |
| `/etc/wireguard/server_privatekey`, `server_publickey` | clés du serveur |
| `/etc/wireguard/clients/<nom>/` | clés et configuration de chaque client |
| `/etc/sysctl.d/wg.conf` | activation du routage IPv4 |
| `/root/add-client.sh` | ajout de clients |

Les clés privées restent sur le serveur. Ne pas publier les fichiers `.conf` des clients : ils contiennent une clé privée.

## Licence

MIT, voir [LICENSE](LICENSE).
