#!/bin/bash

################################################################################
# Script d'Installation WireGuard pour Conteneur LXC Proxmox (Debian 12)
# Auteur: Expert DevOps & SysAdmin Linux
# Description: Installation automatisée d'un serveur WireGuard avec génération
#              du premier client et script helper pour clients futurs
################################################################################

set -euo pipefail  # Arrêt en cas d'erreur, variable non définie, ou erreur dans pipe

################################################################################
# VARIABLES GLOBALES
################################################################################
WG_DIR="/etc/wireguard"
WG_CONF="${WG_DIR}/wg0.conf"
SERVER_PRIV_KEY="${WG_DIR}/server_privatekey"
SERVER_PUB_KEY="${WG_DIR}/server_publickey"
CLIENTS_DIR="${WG_DIR}/clients"
ADD_CLIENT_SCRIPT="/root/add-client.sh"

# Codes couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

################################################################################
# FONCTIONS UTILITAIRES
################################################################################

# Affichage de messages colorés
print_success() {
    echo -e "${GREEN}[✓] $1${NC}"
}

print_error() {
    echo -e "${RED}[✗] $1${NC}" >&2
}

print_warning() {
    echo -e "${YELLOW}[!] $1${NC}"
}

print_info() {
    echo -e "${CYAN}[i] $1${NC}"
}

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# Vérification si le script est exécuté en tant que root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Ce script doit être exécuté en tant que root"
        exit 1
    fi
}

# Vérification de la disponibilité de /dev/net/tun (nécessaire pour LXC)
check_tun() {
    print_info "Vérification de l'interface TUN..."
    if [[ ! -c /dev/net/tun ]]; then
        print_error "Le périphérique /dev/net/tun n'est pas disponible"
        print_warning "Assurez-vous que votre conteneur LXC a l'option 'tun' activée"
        print_info "Sur Proxmox, modifiez le fichier /etc/pve/lxc/[ID].conf et ajoutez:"
        echo -e "   ${YELLOW}lxc.cgroup2.devices.allow: c 10:200 rwm${NC}"
        echo -e "   ${YELLOW}lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file${NC}"
        exit 1
    fi
    print_success "Interface TUN disponible"
}

# Installation des dépendances
install_dependencies() {
    print_header "Installation des Dépendances"

    print_info "Mise à jour de la liste des paquets..."
    apt update -qq

    print_info "Installation des paquets nécessaires..."
    DEBIAN_FRONTEND=noninteractive apt install -y -qq \
        wireguard \
        iptables \
        iproute2 \
        qrencode \
        openresolv \
        curl \
        net-tools >/dev/null 2>&1

    print_success "Toutes les dépendances sont installées"
}

# Détection de l'interface réseau principale
detect_wan_interface() {
    local default_interface
    default_interface=$(ip route | grep default | awk '{print $5}' | head -n1)

    if [[ -z "$default_interface" ]]; then
        print_warning "Impossible de détecter l'interface réseau automatiquement"
        read -p "Entrez le nom de votre interface WAN (ex: eth0): " default_interface
    fi

    echo "$default_interface"
}

# Configuration interactive
interactive_config() {
    print_header "Configuration du Serveur WireGuard"

    # Détection et confirmation de l'interface WAN
    local detected_iface
    detected_iface=$(detect_wan_interface)
    print_info "Interface réseau détectée: ${YELLOW}$detected_iface${NC}"
    read -p "Confirmer cette interface ? (O/n): " confirm_iface

    if [[ "$confirm_iface" =~ ^[Nn]$ ]]; then
        read -p "Entrez le nom de l'interface WAN: " WAN_IFACE
    else
        WAN_IFACE="$detected_iface"
    fi

    # Endpoint (IP publique ou FQDN)
    print_info "\nConfiguration de l'endpoint du serveur"
    print_warning "L'endpoint doit être votre IP publique ou nom de domaine (FQDN)"

    local public_ip
    public_ip=$(curl -s -4 ifconfig.me 2>/dev/null || echo "")

    if [[ -n "$public_ip" ]]; then
        print_info "IP publique détectée: ${YELLOW}$public_ip${NC}"
        read -p "Utiliser cette IP comme endpoint ? (O/n): " use_detected_ip

        if [[ "$use_detected_ip" =~ ^[Nn]$ ]]; then
            read -p "Entrez l'IP publique ou FQDN du serveur: " ENDPOINT
        else
            ENDPOINT="$public_ip"
        fi
    else
        read -p "Entrez l'IP publique ou FQDN du serveur: " ENDPOINT
    fi

    # Configuration du sous-réseau VPN
    print_warning "\n╔════════════════════════════════════════════════════════════════╗"
    print_warning "║ ATTENTION: Évitez d'utiliser 192.168.1.x pour le VPN si       ║"
    print_warning "║ c'est votre réseau local domestique (risque de conflit)       ║"
    print_warning "╚════════════════════════════════════════════════════════════════╝\n"

    read -p "Entrez l'IP du serveur VPN [10.66.66.1]: " SERVER_VPN_IP
    SERVER_VPN_IP="${SERVER_VPN_IP:-10.66.66.1}"

    # Validation basique de l'IP
    if ! [[ "$SERVER_VPN_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_error "Format d'IP invalide"
        exit 1
    fi

    # Extraction du sous-réseau (on suppose /24)
    VPN_SUBNET="${SERVER_VPN_IP%.*}.0/24"

    # Port
    read -p "Entrez le port WireGuard [51820]: " WG_PORT
    WG_PORT="${WG_PORT:-51820}"

    # Validation du port
    if ! [[ "$WG_PORT" =~ ^[0-9]+$ ]] || [ "$WG_PORT" -lt 1 ] || [ "$WG_PORT" -gt 65535 ]; then
        print_error "Port invalide (1-65535)"
        exit 1
    fi

    # DNS
    read -p "Entrez les serveurs DNS [1.1.1.1]: " DNS_SERVERS
    DNS_SERVERS="${DNS_SERVERS:-1.1.1.1}"

    # Récupération de l'IP locale du conteneur LXC
    LOCAL_IP=$(ip addr show "$WAN_IFACE" | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)

    # Résumé de la configuration
    print_header "Résumé de la Configuration"
    echo -e "${CYAN}Interface WAN       :${NC} $WAN_IFACE"
    echo -e "${CYAN}IP Locale (LXC)     :${NC} $LOCAL_IP"
    echo -e "${CYAN}Endpoint            :${NC} $ENDPOINT"
    echo -e "${CYAN}Port                :${NC} $WG_PORT"
    echo -e "${CYAN}IP Serveur VPN      :${NC} $SERVER_VPN_IP"
    echo -e "${CYAN}Sous-réseau VPN     :${NC} $VPN_SUBNET"
    echo -e "${CYAN}DNS                 :${NC} $DNS_SERVERS"
    echo ""

    read -p "Continuer avec cette configuration ? (O/n): " confirm_config
    if [[ "$confirm_config" =~ ^[Nn]$ ]]; then
        print_error "Installation annulée par l'utilisateur"
        exit 0
    fi
}

# Activation de l'IP Forwarding
enable_ip_forwarding() {
    print_info "Activation de l'IP Forwarding..."

    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/wg.conf
    sysctl -p /etc/sysctl.d/wg.conf >/dev/null 2>&1

    print_success "IP Forwarding activé de manière persistante"
}

# Génération des clés du serveur
generate_server_keys() {
    print_info "Génération des clés du serveur..."

    mkdir -p "$WG_DIR"
    cd "$WG_DIR"

    wg genkey | tee "$SERVER_PRIV_KEY" | wg pubkey > "$SERVER_PUB_KEY"

    chmod 600 "$SERVER_PRIV_KEY"
    chmod 644 "$SERVER_PUB_KEY"

    print_success "Clés du serveur générées"
}

# Création du fichier de configuration du serveur
create_server_config() {
    print_info "Création du fichier de configuration du serveur..."

    local server_private_key
    server_private_key=$(cat "$SERVER_PRIV_KEY")

    cat > "$WG_CONF" <<EOF
[Interface]
# Adresse IP privée du serveur VPN
Address = ${SERVER_VPN_IP}/24

# Clé privée du serveur
PrivateKey = ${server_private_key}

# Port d'écoute
ListenPort = ${WG_PORT}

# Règles de pare-feu (NAT/Masquerading)
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ${WAN_IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ${WAN_IFACE} -j MASQUERADE

# Les clients seront ajoutés ci-dessous via 'wg set' ou manuellement
EOF

    chmod 600 "$WG_CONF"
    print_success "Configuration du serveur créée: $WG_CONF"
}

# Activation et démarrage du service WireGuard
start_wireguard_service() {
    print_info "Activation et démarrage du service WireGuard..."

    systemctl enable wg-quick@wg0 >/dev/null 2>&1
    systemctl start wg-quick@wg0

    if systemctl is-active --quiet wg-quick@wg0; then
        print_success "Service WireGuard démarré avec succès"
    else
        print_error "Échec du démarrage du service WireGuard"
        journalctl -u wg-quick@wg0 -n 20
        exit 1
    fi
}

# Génération du script helper pour ajouter des clients futurs
generate_add_client_script() {
    print_info "Génération du script helper add-client.sh..."

    cat > "$ADD_CLIENT_SCRIPT" <<'EOFSCRIPT'
#!/bin/bash

################################################################################
# Script Helper: Ajout de Clients WireGuard
# Généré automatiquement par setup-wireguard.sh
################################################################################

set -euo pipefail

# Variables de configuration (importées depuis l'installation)
WG_DIR="/etc/wireguard"
WG_CONF="${WG_DIR}/wg0.conf"
CLIENTS_DIR="${WG_DIR}/clients"
SERVER_PUB_KEY="${WG_DIR}/server_publickey"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_success() { echo -e "${GREEN}[✓] $1${NC}"; }
print_error() { echo -e "${RED}[✗] $1${NC}" >&2; }
print_info() { echo -e "${CYAN}[i] $1${NC}"; }

# Vérification root
if [[ $EUID -ne 0 ]]; then
    print_error "Ce script doit être exécuté en tant que root"
    exit 1
fi

# Lecture des variables depuis le fichier de configuration
ENDPOINT="__ENDPOINT__"
WG_PORT="__WG_PORT__"
DNS_SERVERS="__DNS_SERVERS__"
VPN_SUBNET="__VPN_SUBNET__"

# Fonction pour obtenir la prochaine IP disponible
get_next_ip() {
    local base_ip="${VPN_SUBNET%.*}"
    local used_ips
    used_ips=$(wg show wg0 allowed-ips 2>/dev/null | awk '{print $2}' | cut -d'/' -f1 | cut -d'.' -f4 | sort -n)

    # Le serveur utilise généralement .1, commencer les clients à .2
    for i in {2..254}; do
        if ! echo "$used_ips" | grep -q "^${i}$"; then
            echo "${base_ip}.${i}"
            return
        fi
    done

    print_error "Aucune IP disponible dans le sous-réseau"
    exit 1
}

# Demander le nom du client
read -p "Entrez le nom du client (ex: smartphone, laptop): " CLIENT_NAME

if [[ -z "$CLIENT_NAME" ]]; then
    print_error "Le nom du client ne peut pas être vide"
    exit 1
fi

# Validation du nom (caractères alphanumériques, tirets, underscores uniquement)
if ! [[ "$CLIENT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    print_error "Le nom du client doit contenir uniquement des lettres, chiffres, tirets et underscores"
    exit 1
fi

# Vérifier si le client existe déjà
CLIENT_DIR="${CLIENTS_DIR}/${CLIENT_NAME}"
if [[ -d "$CLIENT_DIR" ]]; then
    print_error "Un client nommé '$CLIENT_NAME' existe déjà"
    exit 1
fi

print_info "Création du client: $CLIENT_NAME"

# Créer le répertoire du client
mkdir -p "$CLIENT_DIR"
cd "$CLIENT_DIR"

# Générer les clés du client
print_info "Génération des clés..."
CLIENT_PRIV_KEY=$(wg genkey)
CLIENT_PUB_KEY=$(echo "$CLIENT_PRIV_KEY" | wg pubkey)
CLIENT_PSK=$(wg genpsk)

echo "$CLIENT_PRIV_KEY" > "${CLIENT_NAME}_privatekey"
echo "$CLIENT_PUB_KEY" > "${CLIENT_NAME}_publickey"
echo "$CLIENT_PSK" > "${CLIENT_NAME}_presharedkey"

chmod 600 "${CLIENT_NAME}_privatekey" "${CLIENT_NAME}_presharedkey"
chmod 644 "${CLIENT_NAME}_publickey"

# Obtenir la prochaine IP disponible
CLIENT_IP=$(get_next_ip)
print_info "IP attribuée au client: ${YELLOW}${CLIENT_IP}${NC}"

# Lire la clé publique du serveur
SERVER_PUBLIC_KEY=$(cat "$SERVER_PUB_KEY")

# Ajouter le client au serveur WireGuard (dynamiquement)
print_info "Ajout du client au serveur..."
wg set wg0 peer "$CLIENT_PUB_KEY" \
    preshared-key "${CLIENT_NAME}_presharedkey" \
    allowed-ips "${CLIENT_IP}/32"

# Sauvegarder la configuration (pour persistance au redémarrage)
wg-quick save wg0 2>/dev/null || true

# Générer le fichier de configuration client
print_info "Génération du fichier de configuration client..."
cat > "${CLIENT_NAME}.conf" <<EOF
[Interface]
# Nom du client: ${CLIENT_NAME}
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${CLIENT_IP}/32
DNS = ${DNS_SERVERS}

[Peer]
# Serveur WireGuard
PublicKey = ${SERVER_PUBLIC_KEY}
PresharedKey = ${CLIENT_PSK}
Endpoint = ${ENDPOINT}:${WG_PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

chmod 600 "${CLIENT_NAME}.conf"

print_success "Client '$CLIENT_NAME' créé avec succès"
print_info "Fichier de configuration: ${YELLOW}${CLIENT_DIR}/${CLIENT_NAME}.conf${NC}"

# Générer et afficher le QR Code
echo ""
print_info "QR Code pour l'application mobile WireGuard:"
echo ""
qrencode -t ansiutf8 < "${CLIENT_NAME}.conf"
echo ""

print_success "Scannez ce QR Code avec l'application WireGuard mobile"
print_info "Ou copiez le contenu de: ${CLIENT_DIR}/${CLIENT_NAME}.conf"
EOFSCRIPT

    # Remplacer les placeholders par les vraies valeurs
    sed -i "s|__ENDPOINT__|${ENDPOINT}|g" "$ADD_CLIENT_SCRIPT"
    sed -i "s|__WG_PORT__|${WG_PORT}|g" "$ADD_CLIENT_SCRIPT"
    sed -i "s|__DNS_SERVERS__|${DNS_SERVERS}|g" "$ADD_CLIENT_SCRIPT"
    sed -i "s|__VPN_SUBNET__|${VPN_SUBNET}|g" "$ADD_CLIENT_SCRIPT"

    chmod +x "$ADD_CLIENT_SCRIPT"
    print_success "Script helper créé: ${YELLOW}${ADD_CLIENT_SCRIPT}${NC}"
}

# Création automatique du premier client
create_first_client() {
    print_header "Création du Premier Client"

    read -p "Entrez le nom du premier client (ex: smartphone, laptop): " FIRST_CLIENT_NAME

    if [[ -z "$FIRST_CLIENT_NAME" ]]; then
        print_warning "Aucun nom fourni, utilisation de 'client1'"
        FIRST_CLIENT_NAME="client1"
    fi

    # Validation du nom
    if ! [[ "$FIRST_CLIENT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        print_error "Nom invalide, utilisation de 'client1'"
        FIRST_CLIENT_NAME="client1"
    fi

    # Créer le répertoire clients
    mkdir -p "$CLIENTS_DIR"

    CLIENT_DIR="${CLIENTS_DIR}/${FIRST_CLIENT_NAME}"
    mkdir -p "$CLIENT_DIR"
    cd "$CLIENT_DIR"

    # Générer les clés du client
    print_info "Génération des clés du client..."
    CLIENT_PRIV_KEY=$(wg genkey)
    CLIENT_PUB_KEY=$(echo "$CLIENT_PRIV_KEY" | wg pubkey)
    CLIENT_PSK=$(wg genpsk)

    echo "$CLIENT_PRIV_KEY" > "${FIRST_CLIENT_NAME}_privatekey"
    echo "$CLIENT_PUB_KEY" > "${FIRST_CLIENT_NAME}_publickey"
    echo "$CLIENT_PSK" > "${FIRST_CLIENT_NAME}_presharedkey"

    chmod 600 "${FIRST_CLIENT_NAME}_privatekey" "${FIRST_CLIENT_NAME}_presharedkey"
    chmod 644 "${FIRST_CLIENT_NAME}_publickey"

    # Premier client = .2
    local base_ip="${VPN_SUBNET%.*}"
    CLIENT_IP="${base_ip}.2"

    # Lire la clé publique du serveur
    SERVER_PUBLIC_KEY=$(cat "$SERVER_PUB_KEY")

    # Ajouter le client au serveur
    print_info "Ajout du client au serveur..."
    wg set wg0 peer "$CLIENT_PUB_KEY" \
        preshared-key "${FIRST_CLIENT_NAME}_presharedkey" \
        allowed-ips "${CLIENT_IP}/32"

    # Sauvegarder la configuration
    wg-quick save wg0 2>/dev/null || true

    # Générer le fichier de configuration client
    cat > "${FIRST_CLIENT_NAME}.conf" <<EOF
[Interface]
# Nom du client: ${FIRST_CLIENT_NAME}
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${CLIENT_IP}/32
DNS = ${DNS_SERVERS}

[Peer]
# Serveur WireGuard
PublicKey = ${SERVER_PUBLIC_KEY}
PresharedKey = ${CLIENT_PSK}
Endpoint = ${ENDPOINT}:${WG_PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

    chmod 600 "${FIRST_CLIENT_NAME}.conf"

    print_success "Client '$FIRST_CLIENT_NAME' créé avec succès (IP: ${CLIENT_IP})"

    # Afficher le QR Code
    echo ""
    print_info "QR Code pour l'application mobile WireGuard:"
    echo ""
    qrencode -t ansiutf8 < "${FIRST_CLIENT_NAME}.conf"
    echo ""
}

# Affichage du message de fin avec instructions importantes
final_instructions() {
    print_header "Installation Terminée avec Succès !"

    print_success "Le serveur WireGuard est opérationnel"
    print_success "Premier client créé et QR Code généré ci-dessus"

    echo ""
    print_info "Pour ajouter d'autres clients, utilisez:"
    echo -e "   ${YELLOW}${ADD_CLIENT_SCRIPT}${NC}"

    echo ""
    print_warning "╔══════════════════════════════════════════════════════════════════╗"
    print_warning "║                    ACTION REQUISE                                ║"
    print_warning "╠══════════════════════════════════════════════════════════════════╣"
    print_warning "║ N'oubliez pas d'ouvrir le port UDP ${WG_PORT} sur votre Box Internet    ║"
    print_warning "║ et de le rediriger vers l'IP locale de ce conteneur:            ║"
    echo -e "${YELLOW}║                                                                  ║${NC}"
    echo -e "${YELLOW}║   IP du conteneur LXC: ${LOCAL_IP}                          ║${NC}"
    echo -e "${YELLOW}║   Port à rediriger: ${WG_PORT}/UDP                                  ║${NC}"
    print_warning "╚══════════════════════════════════════════════════════════════════╝"

    echo ""
    print_info "Commandes utiles:"
    echo -e "   ${CYAN}wg show${NC}                    - Afficher l'état du serveur"
    echo -e "   ${CYAN}systemctl status wg-quick@wg0${NC} - Statut du service"
    echo -e "   ${CYAN}journalctl -fu wg-quick@wg0${NC}   - Logs en temps réel"
    echo ""
}

################################################################################
# FONCTION PRINCIPALE
################################################################################
main() {
    clear

    print_header "Installation WireGuard - Conteneur LXC Proxmox"
    echo -e "${CYAN}Script d'installation automatisée pour Debian 12${NC}\n"

    # Vérifications préliminaires
    check_root
    check_tun

    # Installation
    install_dependencies
    interactive_config

    # Configuration du serveur
    print_header "Configuration du Serveur WireGuard"
    enable_ip_forwarding
    generate_server_keys
    create_server_config
    start_wireguard_service

    # Génération du script helper
    generate_add_client_script

    # Création du premier client
    create_first_client

    # Instructions finales
    final_instructions
}

# Exécution du script
main "$@"
