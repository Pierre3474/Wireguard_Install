# 🔒 Installation WireGuard sur Conteneur LXC Proxmox

<div align="center">

![WireGuard](https://img.shields.io/badge/WireGuard-88171A?style=for-the-badge&logo=wireguard&logoColor=white)
![Proxmox](https://img.shields.io/badge/Proxmox-E57000?style=for-the-badge&logo=proxmox&logoColor=white)
![Debian](https://img.shields.io/badge/Debian_12-A81D33?style=for-the-badge&logo=debian&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)

**Script d'installation automatisée pour déployer un serveur WireGuard VPN complet sur un conteneur LXC Proxmox**

[Fonctionnalités](#-fonctionnalités) • [Prérequis](#-prérequis) • [Installation](#-installation) • [Usage](#-utilisation) • [Sécurité](#-sécurité)

</div>

---

## 📋 Table des Matières

- [Fonctionnalités](#-fonctionnalités)
- [Prérequis](#-prérequis)
- [Étape 1 : Création du Conteneur LXC](#-étape-1--création-du-conteneur-lxc-sur-proxmox)
- [Étape 2 : Modifications Critiques du LXC](#-étape-2--modifications-critiques-du-conteneur-lxc)
- [Étape 3 : Installation du Script](#-étape-3--installation-et-exécution-du-script)
- [Étape 4 : Configuration de votre Box Internet](#-étape-4--configuration-de-votre-box-internet)
- [Utilisation](#-utilisation)
- [Ajout de Clients](#-ajout-de-clients-supplémentaires)
- [Dépannage](#-dépannage)
- [Sécurité](#-sécurité)
- [Architecture](#-architecture)
- [FAQ](#-faq)
- [Licence](#-licence)

---

## ✨ Fonctionnalités

✅ **Installation entièrement automatisée** sur Debian 12
✅ **Configuration interactive** avec détection automatique de l'interface réseau
✅ **Génération automatique** du premier client avec QR Code
✅ **Script helper** (`add-client.sh`) pour ajouter facilement de nouveaux clients
✅ **Sécurité renforcée** : Clés preshared, permissions strictes
✅ **NAT/Masquerading** automatique via iptables
✅ **IP Forwarding** activé de manière persistante
✅ **QR Codes** pour configuration mobile instantanée
✅ **Gestion des erreurs** complète et messages colorés

---

## 🎯 Prérequis

Avant de commencer, assurez-vous d'avoir :

- ✅ **Proxmox VE** (version 7.x ou 8.x recommandée)
- ✅ **Accès SSH** à votre serveur Proxmox
- ✅ **IP Publique fixe** ou **Nom de Domaine (FQDN)** pointant vers votre serveur
- ✅ **Accès administrateur** à votre Box Internet (pour la redirection de port)
- ✅ Connexion Internet stable

---

## 🚀 Étape 1 : Création du Conteneur LXC sur Proxmox

### 1.1 Via l'Interface Web Proxmox

1. **Connectez-vous** à l'interface web Proxmox : `https://[IP_PROXMOX]:8006`

2. **Créez un nouveau conteneur LXC** :
   - Cliquez sur **"Create CT"** (bouton en haut à droite)

3. **Configuration générale** :
   - **Hostname** : `wireguard-vpn` (ou le nom de votre choix)
   - **Password** : Définissez un mot de passe root sécurisé
   - ✅ Cochez **"Unprivileged container"** (recommandé)

4. **Template** :
   - Sélectionnez **Debian 12 (Bookworm)** dans la liste des templates
   - Si vous n'avez pas ce template, téléchargez-le depuis : **local > CT Templates > Templates**

5. **Disque** :
   - **Disk size** : `8 GB` minimum (recommandé : 10-16 GB)
   - **Storage** : Choisissez votre stockage (local-lvm, local-zfs, etc.)

6. **CPU** :
   - **Cores** : `1` (suffisant pour un usage personnel, 2 pour haute disponibilité)

7. **Mémoire** :
   - **Memory (RAM)** : `512 MB` (recommandé : 1024 MB)
   - **Swap** : `512 MB`

8. **Réseau** :
   - **Name** : `eth0`
   - **Bridge** : `vmbr0` (votre bridge réseau principal)
   - **IPv4** : DHCP ou Statique (notez l'IP locale du conteneur)
   - **IPv6** : DHCP ou laisser vide

9. **DNS** :
   - Utilisez les DNS de votre choix (ex: `1.1.1.1` ou `8.8.8.8`)

10. **Confirmez** et créez le conteneur (ne le démarrez PAS encore)

### 1.2 Via Ligne de Commande (Alternative)

Connectez-vous en SSH à votre serveur Proxmox :

```bash
ssh root@[IP_PROXMOX]
```

Téléchargez le template Debian 12 (si non présent) :

```bash
pveam update
pveam download local debian-12-standard_12.2-1_amd64.tar.zst
```

Créez le conteneur :

```bash
pct create 100 local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst \
  --hostname wireguard-vpn \
  --memory 1024 \
  --swap 512 \
  --cores 1 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --storage local-lvm \
  --rootfs local-lvm:8 \
  --unprivileged 1 \
  --features nesting=1 \
  --password
```

> **Note** : Remplacez `100` par l'ID de conteneur souhaité (généralement auto-incrémenté)

---

## ⚙️ Étape 2 : Modifications Critiques du Conteneur LXC

**⚠️ IMPORTANT** : WireGuard nécessite l'accès au périphérique `/dev/net/tun`. Par défaut, les conteneurs LXC n'y ont pas accès.

### 2.1 Activation du Périphérique TUN

Sur votre **hôte Proxmox** (pas dans le conteneur), éditez le fichier de configuration du conteneur :

```bash
nano /etc/pve/lxc/[ID_CONTENEUR].conf
```

> **Remplacez `[ID_CONTENEUR]`** par l'ID réel de votre conteneur (ex: `100`)

Ajoutez les lignes suivantes **à la fin du fichier** :

```conf
# Activation de l'interface TUN pour WireGuard
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```

**Pour les anciens systèmes Proxmox (cgroup v1)**, utilisez plutôt :

```conf
lxc.cgroup.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```

#### 🎓 Comprendre la Configuration LXC (Pédagogie)

**Pourquoi ces deux lignes sont-elles nécessaires ?**

Les conteneurs LXC sont isolés du noyau de l'hôte pour des raisons de sécurité. Par défaut, ils n'ont accès qu'à un ensemble limité de périphériques système. WireGuard, étant un module du noyau Linux, nécessite l'accès au périphérique `/dev/net/tun` pour créer des interfaces réseau virtuelles.

Voici ce que font ces deux lignes :

**1️⃣ `lxc.cgroup2.devices.allow: c 10:200 rwm`**

Cette ligne **donne la permission (la clé)** au conteneur d'accéder au périphérique TUN.

- **`c 10:200`** : Identifie le périphérique TUN/TAP (caractère majeur 10, mineur 200)
- **`rwm`** : Autorise les opérations **R**ead (lecture), **W**rite (écriture), **M**knod (création)
- **Analogie** : C'est comme donner une clé à votre conteneur pour qu'il puisse déverrouiller la porte du module TUN

**2️⃣ `lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file`**

Cette ligne **crée le fichier (la serrure)** `/dev/net/tun` à l'intérieur du conteneur.

- **`bind`** : Monte le périphérique de l'hôte dans le conteneur (liaison)
- **`create=file`** : Crée le fichier spécial si inexistant dans le conteneur
- **Analogie** : C'est comme installer la serrure sur la porte du conteneur

**⚠️ Sécurité et Isolation**

Ces modifications touchent à l'isolation du noyau. Vous autorisez délibérément le conteneur à accéder à une fonctionnalité système de bas niveau (le module TUN). C'est nécessaire pour WireGuard, mais gardez à l'esprit que :

- ✅ WireGuard est un logiciel sûr et audité
- ✅ L'accès est limité uniquement au périphérique TUN
- ⚠️ Ne donnez ces permissions qu'aux conteneurs de confiance
- ⚠️ Ne partagez jamais les clés privées générées

**En résumé** : Sans ces deux lignes, votre conteneur a une porte (le besoin d'accéder à TUN), mais ni serrure ni clé. Avec ces lignes, vous installez la serrure ET donnez la clé, permettant à WireGuard de fonctionner correctement.

---

### 2.2 Activation du Nesting (Optionnel mais Recommandé)

Pour une meilleure compatibilité, activez le nesting :

```conf
features: nesting=1
```

### 2.3 Exemple de Configuration Complète

Voici à quoi devrait ressembler votre fichier `/etc/pve/lxc/100.conf` :

```conf
arch: amd64
cores: 1
hostname: wireguard-vpn
memory: 1024
swap: 512
net0: name=eth0,bridge=vmbr0,hwaddr=XX:XX:XX:XX:XX:XX,ip=dhcp,type=veth
ostype: debian
rootfs: local-lvm:vm-100-disk-0,size=8G
unprivileged: 1
features: nesting=1

# Activation TUN pour WireGuard
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```

### 2.4 Démarrage du Conteneur

Démarrez maintenant le conteneur :

```bash
pct start [ID_CONTENEUR]
```

Vérifiez que le conteneur est bien démarré :

```bash
pct status [ID_CONTENEUR]
```

---

## 🛠️ Étape 3 : Installation et Exécution du Script

### 3.1 Connexion au Conteneur

Depuis votre hôte Proxmox, connectez-vous au conteneur :

```bash
pct enter [ID_CONTENEUR]
```

**OU** via SSH directement (si vous avez configuré une IP statique) :

```bash
ssh root@[IP_CONTENEUR]
```

### 3.2 Installation de Git

Une fois connecté au conteneur en tant que root, installez Git :

```bash
apt update
apt install -y git
```

### 3.3 Clonage du Dépôt

Clonez ce dépôt GitHub dans le répertoire de votre choix :

```bash
cd /root
git clone https://github.com/Pierre3474/Wireguard_Install.git
cd Wireguard_Install
```

### 3.4 Rendre le Script Exécutable

Donnez les permissions d'exécution au script :

```bash
chmod +x setup-wireguard.sh
```

### 3.5 Lancement du Script

Exécutez le script d'installation :

```bash
./setup-wireguard.sh
```

### 3.6 Configuration Interactive

Le script vous guidera à travers les étapes suivantes :

1. **Vérification de l'environnement** (interface TUN, root, etc.)
2. **Installation des dépendances** (WireGuard, iptables, qrencode, etc.)
3. **Configuration interactive** :
   - ✅ **Interface WAN** : Le script détecte automatiquement `eth0` (confirmation demandée)
   - ✅ **Endpoint** : Votre IP publique (détectée automatiquement via `ifconfig.me`) ou FQDN
   - ✅ **Sous-réseau VPN** : Par défaut `10.66.66.1/24`
     - ⚠️ **Alerte de sécurité** : Le script affiche un **avertissement jaune** vous rappelant d'éviter d'utiliser `192.168.1.x` pour le VPN si c'est votre réseau local domestique (risque de conflit de routage)
     - 💡 Le sous-réseau par défaut `10.66.66.0/24` est choisi spécifiquement pour éviter les conflits avec les Box Internet classiques (qui utilisent généralement `192.168.0.x` ou `192.168.1.x`)
   - ✅ **Port** : Par défaut `51820` (UDP)
   - ✅ **DNS** : Par défaut `1.1.1.1` (Cloudflare)
4. **Génération des clés** du serveur (privée/publique avec permissions `chmod 600`)
5. **Création du premier client** (nom personnalisable)
6. **Affichage du QR Code** pour connexion mobile instantanée

### 3.7 Exemple d'Exécution

```
========================================
Installation WireGuard - Conteneur LXC Proxmox
========================================

[i] Vérification de l'interface TUN...
[✓] Interface TUN disponible

========================================
Installation des Dépendances
========================================

[i] Mise à jour de la liste des paquets...
[i] Installation des paquets nécessaires...
[✓] Toutes les dépendances sont installées

========================================
Configuration du Serveur WireGuard
========================================

[i] Interface réseau détectée: eth0
Confirmer cette interface ? (O/n): O

[i] Configuration de l'endpoint du serveur
[!] L'endpoint doit être votre IP publique ou nom de domaine (FQDN)
[i] IP publique détectée: 203.0.113.50
Utiliser cette IP comme endpoint ? (O/n): O

[!] ╔════════════════════════════════════════════════════════════════╗
[!] ║ ATTENTION: Évitez d'utiliser 192.168.1.x pour le VPN si       ║
[!] ║ c'est votre réseau local domestique (risque de conflit)       ║
[!] ╚════════════════════════════════════════════════════════════════╝

Entrez l'IP du serveur VPN [10.66.66.1]: ⏎ (Entrée = défaut)
Entrez le port WireGuard [51820]: ⏎
Entrez les serveurs DNS [1.1.1.1]: ⏎

========================================
Résumé de la Configuration
========================================

Interface WAN       : eth0
IP Locale (LXC)     : 192.168.1.100
Endpoint            : 203.0.113.50
Port                : 51820
IP Serveur VPN      : 10.66.66.1
Sous-réseau VPN     : 10.66.66.0/24
DNS                 : 1.1.1.1

Continuer avec cette configuration ? (O/n): O

[i] Activation de l'IP Forwarding...
[✓] IP Forwarding activé de manière persistante
[i] Génération des clés du serveur...
[✓] Clés du serveur générées
[i] Création du fichier de configuration du serveur...
[✓] Configuration du serveur créée: /etc/wireguard/wg0.conf
[i] Activation et démarrage du service WireGuard...
[✓] Service WireGuard démarré avec succès
[i] Génération du script helper add-client.sh...
[✓] Script helper créé: /root/add-client.sh

========================================
Création du Premier Client
========================================

Entrez le nom du premier client (ex: smartphone, laptop): smartphone
[i] Génération des clés du client...
[i] Ajout du client au serveur...
[✓] Client 'smartphone' créé avec succès (IP: 10.66.66.2)

[i] QR Code pour l'application mobile WireGuard:

█████████████████████████████████
█████████████████████████████████
████ ▄▄▄▄▄ █▀█ █▄▄▀▄█ ▄▄▄▄▄ ████
████ █   █ █▀▀▀█ ▀▄ █ █   █ ████
[... QR Code affiché ...]

========================================
Installation Terminée avec Succès !
========================================

[✓] Le serveur WireGuard est opérationnel
[✓] Premier client créé et QR Code généré ci-dessus

[i] Pour ajouter d'autres clients, utilisez:
   /root/add-client.sh

[!] ╔══════════════════════════════════════════════════════════════════╗
[!] ║                    ACTION REQUISE                                ║
[!] ╠══════════════════════════════════════════════════════════════════╣
[!] ║ N'oubliez pas d'ouvrir le port UDP 51820 sur votre Box Internet ║
[!] ║ et de le rediriger vers l'IP locale de ce conteneur:            ║
[!] ║                                                                  ║
[!] ║   IP du conteneur LXC: 192.168.1.100                             ║
[!] ║   Port à rediriger: 51820/UDP                                    ║
[!] ╚══════════════════════════════════════════════════════════════════╝

[i] Commandes utiles:
   wg show                    - Afficher l'état du serveur
   systemctl status wg-quick@wg0 - Statut du service
   journalctl -fu wg-quick@wg0   - Logs en temps réel
```

---

## 🌐 Étape 4 : Configuration de votre Box Internet

**⚠️ CRITIQUE** : Pour que vos clients puissent se connecter depuis l'extérieur, vous devez configurer une redirection de port (NAT/PAT) sur votre Box Internet.

### 4.1 Redirection de Port

Connectez-vous à l'interface d'administration de votre Box Internet :

| Fournisseur | URL d'accès                      |
|-------------|----------------------------------|
| **Freebox** | http://mafreebox.freebox.fr      |
| **Livebox** | http://192.168.1.1               |
| **SFR Box** | http://192.168.1.1               |
| **Bbox**    | http://192.168.1.254             |

### 4.2 Créer la Règle de Redirection

Cherchez la section **"Redirection de ports"** ou **"NAT/PAT"** et créez une règle :

| Paramètre            | Valeur                          |
|----------------------|---------------------------------|
| **Nom**              | WireGuard VPN                   |
| **Port externe**     | `51820` (ou le port choisi)     |
| **Protocole**        | **UDP** (IMPORTANT : pas TCP)   |
| **IP de destination**| IP locale du conteneur LXC      |
| **Port interne**     | `51820`                         |

### 4.3 Exemple pour Freebox

1. Allez dans **"Paramètres de la Freebox"** > **"Mode avancé"** > **"Gestion des ports"**
2. Cliquez sur **"Ajouter une redirection"**
3. Remplissez :
   - **IP de destination** : `192.168.1.100` (votre conteneur LXC)
   - **Port de début** : `51820`
   - **Port de fin** : `51820`
   - **Protocole** : **UDP**
   - **IP source** : `Toutes`
4. **Sauvegardez**

### 4.4 Vérification

Testez que le port est bien ouvert depuis l'extérieur :

```bash
# Depuis un autre réseau (4G, autre connexion)
nc -u -v [VOTRE_IP_PUBLIQUE] 51820
```

---

## 📱 Utilisation

### Connexion depuis un Client Mobile

1. **Téléchargez** l'application WireGuard :
   - **Android** : [Google Play Store](https://play.google.com/store/apps/details?id=com.wireguard.android)
   - **iOS** : [App Store](https://apps.apple.com/app/wireguard/id1441195209)

2. **Scannez le QR Code** affiché par le script

3. **Activez** la connexion VPN

4. **Vérifiez** votre connexion :
   - Allez sur https://whatismyipaddress.com/
   - Vous devriez voir l'IP publique de votre serveur

### Connexion depuis un Client Desktop

Le fichier de configuration se trouve dans :

```
/etc/wireguard/clients/[NOM_CLIENT]/[NOM_CLIENT].conf
```

**Linux** :

```bash
# Copiez le fichier de configuration
cp /etc/wireguard/clients/laptop/laptop.conf ~/wg0.conf

# Importez et activez
wg-quick up ~/wg0.conf
```

**Windows/macOS** :

1. Téléchargez l'application WireGuard
2. Importez le fichier `.conf`
3. Activez la connexion

---

## ➕ Ajout de Clients Supplémentaires

### À Propos du Script Helper `add-client.sh`

**Important** : Le fichier `/root/add-client.sh` n'est **pas livré avec le dépôt GitHub**. Il est **généré automatiquement** par le script d'installation `setup-wireguard.sh` lors de la première exécution.

Ce script helper est l'**outil officiel** pour ajouter de nouveaux clients à votre serveur WireGuard. Il contient toute la configuration spécifique à votre installation (endpoint, port, DNS, sous-réseau VPN) et garantit la cohérence de vos configurations.

### Où se trouve-t-il ?

Après avoir exécuté `setup-wireguard.sh`, vous trouverez le script généré ici :

```
/root/add-client.sh
```

### Utilisation du Script Helper

Pour ajouter un nouveau client, exécutez simplement :

```bash
/root/add-client.sh
```

Le script vous demandera :
- Le **nom du client** (ex: `laptop`, `tablet`, `phone2`)
  - ⚠️ Uniquement des caractères alphanumériques, tirets et underscores
  - ⚠️ Le nom doit être unique (pas de doublon)

Il générera automatiquement :
- ✅ Les **clés** (privée, publique, preshared) avec permissions `chmod 600`
- ✅ Une **IP disponible** dans le sous-réseau (calcul automatique de la prochaine IP libre)
- ✅ Le **fichier de configuration** `.conf` prêt à l'emploi
- ✅ L'**ajout du client** au serveur WireGuard (via `wg set`)
- ✅ Le **QR Code** affiché dans le terminal pour scan mobile

### Exemple

```bash
root@wireguard-vpn:~# /root/add-client.sh

Entrez le nom du client (ex: smartphone, laptop): laptop

[i] Création du client: laptop
[i] Génération des clés...
[i] IP attribuée au client: 10.66.66.3
[i] Ajout du client au serveur...
[i] Génération du fichier de configuration client...
[✓] Client 'laptop' créé avec succès
[i] Fichier de configuration: /etc/wireguard/clients/laptop/laptop.conf

[i] QR Code pour l'application mobile WireGuard:

█████████████████████████████████
[... QR Code affiché ...]
```

---

## 🔍 Dépannage

### ⚠️ Problème n°1 : Interface TUN non disponible (ERREUR LA PLUS FRÉQUENTE)

**Symptômes** :

Le script affiche cette erreur au démarrage :

```
[✗] Le périphérique /dev/net/tun n'est pas disponible
Assurez-vous que votre conteneur LXC a l'option 'tun' activée
Sur Proxmox, modifiez le fichier /etc/pve/lxc/[ID].conf et ajoutez:
   lxc.cgroup2.devices.allow: c 10:200 rwm
   lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```

**Cause** :

🚨 **Cette erreur est TOUJOURS causée par l'oubli de l'[Étape 2](#-étape-2--modifications-critiques-du-conteneur-lxc)** (modifications du fichier de configuration LXC sur l'hôte Proxmox).

Par défaut, les conteneurs LXC sont isolés et **n'ont pas accès au périphérique `/dev/net/tun`** nécessaire à WireGuard. Vous **DEVEZ** autoriser cet accès manuellement depuis l'hôte Proxmox (PVE), **PAS depuis l'intérieur du conteneur**.

**Solution** :

1. **Sur votre HÔTE Proxmox** (pas dans le conteneur), arrêtez le conteneur :

```bash
pct stop [ID_CONTENEUR]
```

2. **Sur votre HÔTE Proxmox**, éditez le fichier de configuration :

```bash
nano /etc/pve/lxc/[ID_CONTENEUR].conf
```

3. Ajoutez ces lignes **à la fin du fichier** :

```conf
# Activation TUN pour WireGuard
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```

> **Note** : Pour les anciens systèmes Proxmox (cgroup v1), utilisez `lxc.cgroup.devices.allow` au lieu de `lxc.cgroup2.devices.allow`

4. **Sauvegardez** le fichier (`Ctrl+O`, `Entrée`, `Ctrl+X`)

5. **Redémarrez** le conteneur :

```bash
pct start [ID_CONTENEUR]
```

6. **Vérifiez** que le périphérique TUN est maintenant accessible **dans le conteneur** :

```bash
pct enter [ID_CONTENEUR]
ls -l /dev/net/tun
```

Vous devriez voir :

```
crw-rw-rw- 1 root root 10, 200 Nov 29 12:34 /dev/net/tun
```

7. **Relancez** le script d'installation :

```bash
cd /root/Wireguard_Install
./setup-wireguard.sh
```

**⚠️ Rappel Important** :

- ❌ **NE PAS** essayer de créer `/dev/net/tun` manuellement dans le conteneur (ça ne fonctionnera pas)
- ❌ **NE PAS** installer des modules noyau dans le conteneur (les conteneurs LXC partagent le noyau de l'hôte)
- ✅ **TOUJOURS** modifier le fichier de configuration **sur l'hôte Proxmox**

---

### Problème n°2 : Le service WireGuard ne démarre pas

**Vérifiez les logs** :

```bash
journalctl -u wg-quick@wg0 -n 50
```

**Vérifiez la configuration** :

```bash
wg-quick up wg0
```

Si vous voyez une erreur liée à l'interface, vérifiez que l'interface WAN est correcte dans `/etc/wireguard/wg0.conf`

### Problème n°3 : Les clients ne peuvent pas se connecter

**Vérifiez que le port est ouvert sur le serveur** :

```bash
ss -ulnp | grep 51820
```

Vous devriez voir :

```
UNCONN 0 0 0.0.0.0:51820 0.0.0.0:* users:(("wg",pid=1234,fd=3))
```

**Vérifiez la redirection de port** sur votre Box Internet (voir [Étape 4](#-étape-4--configuration-de-votre-box-internet))

**Testez la connectivité** depuis l'extérieur :

```bash
# Depuis un autre réseau (4G, autre connexion), testez la connectivité
ping [IP_PUBLIQUE_SERVEUR]
nc -u -v -z [IP_PUBLIQUE_SERVEUR] 51820
```

**Checklist** :
- ✅ Le port UDP 51820 est bien redirigé vers l'IP locale du conteneur sur votre Box
- ✅ Le service WireGuard est actif : `systemctl status wg-quick@wg0`
- ✅ Le firewall de l'hôte Proxmox autorise le trafic UDP sur le port 51820

---

### Problème n°4 : Pas d'accès Internet via le VPN

**Symptôme** : Vous êtes connecté au VPN, mais vous ne pouvez pas naviguer sur Internet.

**Vérifiez l'IP Forwarding** :

```bash
sysctl net.ipv4.ip_forward
# Doit retourner: net.ipv4.ip_forward = 1
```

**Vérifiez les règles iptables** :

```bash
iptables -t nat -L POSTROUTING -v
```

Vous devriez voir une règle `MASQUERADE` pour l'interface WAN (eth0).

**Réappliquez les règles** :

```bash
systemctl restart wg-quick@wg0
```

**Vérifiez l'interface WAN** dans `/etc/wireguard/wg0.conf` :

```bash
grep PostUp /etc/wireguard/wg0.conf
```

Assurez-vous que l'interface mentionnée (ex: `eth0`) correspond bien à votre interface réseau principale.

---

### Problème n°5 : DNS ne fonctionne pas

**Symptôme** : Vous êtes connecté au VPN, vous avez accès à Internet via IP, mais pas par noms de domaine.

**Sur le client**, vérifiez que le DNS est bien configuré dans le fichier `.conf` :

```conf
[Interface]
DNS = 1.1.1.1
```

**Testez la résolution DNS** depuis le client :

```bash
nslookup google.com 1.1.1.1
```

**Sur certains systèmes**, vous devrez peut-être installer `openresolv` sur le client :

```bash
# Linux
apt install openresolv  # Debian/Ubuntu
dnf install openresolv  # Fedora

# Puis redémarrez le tunnel
wg-quick down wg0
wg-quick up wg0
```

---

## 🔒 Sécurité

### Bonnes Pratiques

✅ **Clés Preshared** : Le script génère automatiquement des clés preshared pour une sécurité post-quantique
✅ **Permissions strictes** : Tous les fichiers de clés ont `chmod 600`
✅ **Pare-feu** : Seul le port WireGuard (UDP) est exposé
✅ **AllowedIPs** : Les clients sont isolés (`/32`), aucun client ne peut communiquer avec un autre

### Recommandations

🔹 **Changez les clés régulièrement** (tous les 6-12 mois)
🔹 **Utilisez un nom de domaine** (FQDN) au lieu d'une IP publique pour l'endpoint
🔹 **Configurez fail2ban** pour bloquer les tentatives de connexion suspectes
🔹 **Sauvegardez** le répertoire `/etc/wireguard` de manière sécurisée
🔹 **Surveillez les logs** : `journalctl -fu wg-quick@wg0`

### Rotation des Clés

Pour régénérer les clés du serveur :

```bash
cd /etc/wireguard
wg genkey | tee server_privatekey | wg pubkey > server_publickey
chmod 600 server_privatekey

# Redémarrez le service
systemctl restart wg-quick@wg0
```

**⚠️ ATTENTION** : Vous devrez reconfigurer **tous les clients** avec la nouvelle clé publique du serveur.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Internet                            │
└──────────────────────┬──────────────────────────────────┘
                       │
                       │ UDP:51820
                       ▼
┌─────────────────────────────────────────────────────────┐
│                  Box Internet                           │
│              (Redirection de Port)                      │
└──────────────────────┬──────────────────────────────────┘
                       │
                       │ 192.168.1.100:51820
                       ▼
┌─────────────────────────────────────────────────────────┐
│         Serveur Proxmox (Hôte Physique)                │
│                                                         │
│   ┌──────────────────────────────────────────────┐    │
│   │   Conteneur LXC (wireguard-vpn)              │    │
│   │                                               │    │
│   │   ┌─────────────────────────────────┐        │    │
│   │   │   WireGuard Server (wg0)        │        │    │
│   │   │   IP: 10.66.66.1/24             │        │    │
│   │   │   Port: 51820/UDP               │        │    │
│   │   └─────────────────────────────────┘        │    │
│   │                                               │    │
│   │   /etc/wireguard/                            │    │
│   │   ├── wg0.conf (serveur)                     │    │
│   │   ├── clients/                               │    │
│   │   │   ├── client1/                           │    │
│   │   │   │   ├── client1.conf                   │    │
│   │   │   │   ├── client1_privatekey             │    │
│   │   │   │   └── client1_publickey              │    │
│   │   │   └── laptop/                            │    │
│   │   │       └── ...                            │    │
│   └──────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
                       ▲
                       │
           ┌───────────┼───────────┐
           │           │           │
           ▼           ▼           ▼
     ┌─────────┐ ┌─────────┐ ┌─────────┐
     │ Client1 │ │ Laptop  │ │ Phone   │
     │10.66.66.2│ │10.66.66.3│ │10.66.66.4│
     └─────────┘ └─────────┘ └─────────┘
```

### Flux de Trafic

1. **Client → Serveur** : Le client chiffre les données et les envoie au serveur WireGuard (UDP:51820)
2. **Serveur → Internet** : Le serveur déchiffre, applique le NAT (MASQUERADE) et route vers Internet
3. **Internet → Serveur** : Les réponses reviennent au serveur
4. **Serveur → Client** : Le serveur chiffre et renvoie au client concerné

---

## ❓ FAQ

### Q : Puis-je utiliser ce script sur une VM au lieu d'un conteneur LXC ?

**R** : Oui, le script fonctionne également sur une VM Debian 12. Vous pouvez ignorer les étapes liées à l'activation du périphérique TUN (déjà disponible dans les VMs).

### Q : Combien de clients puis-je ajouter ?

**R** : Avec un sous-réseau `/24`, vous pouvez théoriquement ajouter jusqu'à 253 clients (`.2` à `.254`). En pratique, les performances dépendront de votre matériel.

### Q : Puis-je changer le port après l'installation ?

**R** : Oui, éditez `/etc/wireguard/wg0.conf`, changez `ListenPort`, redémarrez le service (`systemctl restart wg-quick@wg0`), et mettez à jour la redirection de port sur votre Box.

### Q : Le VPN fonctionne-t-il avec IPv6 ?

**R** : Le script actuel est configuré pour IPv4. Pour IPv6, ajoutez `Address` et `AllowedIPs` IPv6 dans les configurations serveur et client.

### Q : Comment désinstaller WireGuard ?

**R** :

```bash
systemctl stop wg-quick@wg0
systemctl disable wg-quick@wg0
apt remove --purge wireguard
rm -rf /etc/wireguard
```

### Q : Puis-je utiliser un autre DNS que Cloudflare ?

**R** : Oui, lors de la configuration interactive, spécifiez vos DNS préférés (ex: `8.8.8.8` pour Google, `9.9.9.9` pour Quad9).

### Q : Le VPN affecte-t-il les performances ?

**R** : WireGuard est extrêmement performant. Sur du matériel moderne, l'impact est minime (< 5% de latence supplémentaire).

### Q : Comment voir les clients connectés ?

**R** :

```bash
wg show
```

Vous verrez la liste des clients avec leur dernière handshake et data transfert.

### Q : Puis-je utiliser ce VPN pour contourner les restrictions géographiques ?

**R** : Techniquement oui, mais assurez-vous de respecter les lois locales et les conditions d'utilisation des services.

---

## 📊 Commandes Utiles

| Commande | Description |
|----------|-------------|
| `wg show` | Afficher l'état du serveur et des clients connectés |
| `wg show wg0` | Afficher l'état de l'interface wg0 uniquement |
| `systemctl status wg-quick@wg0` | Statut du service WireGuard |
| `systemctl restart wg-quick@wg0` | Redémarrer le service |
| `journalctl -fu wg-quick@wg0` | Logs en temps réel |
| `iptables -t nat -L -v` | Afficher les règles NAT |
| `cat /etc/wireguard/wg0.conf` | Voir la configuration du serveur |
| `/root/add-client.sh` | Ajouter un nouveau client |
| `wg-quick down wg0` | Arrêter l'interface (sans désactiver le service) |
| `wg-quick up wg0` | Démarrer l'interface manuellement |

---

## 🤝 Contribution

Les contributions sont les bienvenues ! Si vous trouvez un bug ou souhaitez améliorer le script :

1. **Forkez** le projet
2. **Créez** une branche pour votre fonctionnalité (`git checkout -b feature/AmazingFeature`)
3. **Committez** vos changements (`git commit -m 'Add some AmazingFeature'`)
4. **Pushez** vers la branche (`git push origin feature/AmazingFeature`)
5. **Ouvrez** une Pull Request

---

## 📝 Changelog

### Version 1.0.0 (2025-11-29)

- ✅ Release initiale
- ✅ Installation automatisée WireGuard
- ✅ Génération du premier client
- ✅ Script helper pour clients supplémentaires
- ✅ QR Codes pour mobile
- ✅ Gestion complète des erreurs

---

## 📄 Licence

Ce projet est distribué sous licence **MIT**. Voir le fichier `LICENSE` pour plus de détails.

---

## ⚠️ Disclaimer

Ce script est fourni "tel quel", sans garantie d'aucune sorte. L'auteur ne peut être tenu responsable des dommages directs ou indirects résultant de l'utilisation de ce script. Utilisez-le à vos propres risques.

**Sécurité** : Assurez-vous de comprendre les implications de l'ouverture d'un VPN sur votre réseau domestique. Protégez toujours vos clés privées et ne les partagez jamais.

---

## 🙏 Remerciements

- **[WireGuard®](https://www.wireguard.com/)** - Pour ce VPN révolutionnaire
- **[Proxmox VE](https://www.proxmox.com/)** - Pour la meilleure plateforme de virtualisation open-source
- **[Debian](https://www.debian.org/)** - Pour la stabilité et la fiabilité

---

<div align="center">

**Fait avec ❤️ pour la communauté DevOps & SysAdmin**

[![GitHub](https://img.shields.io/badge/GitHub-Pierre3474-181717?style=for-the-badge&logo=github)](https://github.com/Pierre3474)

</div>
