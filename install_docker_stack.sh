#!/bin/bash

# Script di installazione per Docker, Portainer e Jellyfin su Rocky Linux 9.5
# Author: Luca Sabato, SystemAdmin, defence ITA 
# Funzione per verificare se lo script è eseguito come root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Questo script deve essere eseguito come root"
        exit 1
    fi
}

# Funzione per determinare la home directory corretta
get_user_home() {
    if [ -n "$SUDO_USER" ]; then
        echo "/home/$SUDO_USER"
    else
        echo "$HOME"
    fi
}

# Funzione per installare i pacchetti base
install_base_packages() {
    echo "Installazione dei pacchetti base..."
    dnf install -y nano bash-completion cockpit cockpit-files
    systemctl enable --now cockpit.socket
}

# Funzione per installare Docker
install_docker() {
    echo "Configurazione del repository Docker..."
    dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
    
    echo "Installazione di Docker e componenti..."
    dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    echo "Abilitazione e avvio di Docker..."
    systemctl enable --now docker
    
    echo "Aggiunta dell'utente al gruppo docker..."
    if [ -n "$SUDO_USER" ]; then
        usermod -aG docker "$SUDO_USER"
    else
        usermod -aG docker "$(whoami)"
    fi
}

# Funzione per configurare Jellyfin
setup_jellyfin() {
    local USER_HOME=$(get_user_home)
    local JELLYFIN_DIR="$USER_HOME/jellyfin"
    
    echo "Configurazione di Jellyfin in $JELLYFIN_DIR..."
    mkdir -p "$JELLYFIN_DIR/config" "$JELLYFIN_DIR/cache" "$JELLYFIN_DIR/media"
    chmod -R 0777 "$JELLYFIN_DIR/media"
    
    cat > "$JELLYFIN_DIR/docker-compose.yml" <<EOF
version: '3.8'
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    network_mode: host
    volumes:
      - ./config:/config
      - ./cache:/cache
      - ./media:/media
    restart: unless-stopped
EOF
    
    echo "Avvio del container Jellyfin..."
    (cd "$JELLYFIN_DIR" && docker compose up -d)
    
    echo "Configurazione del firewall per Jellyfin..."
    firewall-cmd --permanent --add-port=8096/tcp
    firewall-cmd --permanent --add-port=8096/udp
}

# Funzione per configurare Portainer
setup_portainer() {
    local USER_HOME=$(get_user_home)
    local PORTAINER_DIR="$USER_HOME/portainer"
    
    echo "Configurazione di Portainer in $PORTAINER_DIR..."
    mkdir -p "$PORTAINER_DIR"
    
    cat > "$PORTAINER_DIR/docker-compose.yml" <<EOF
version: '3'
services:
  portainer:
    image: portainer/portainer-ce
    ports:
      - 9000:9000
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    restart: always
volumes:
  portainer_data:
EOF
    
    echo "Avvio del container Portainer..."
    (cd "$PORTAINER_DIR" && docker compose up -d)
    
    echo "Configurazione del firewall per Portainer..."
    firewall-cmd --permanent --add-port=9000/tcp
}

# Funzione per impostare i permessi corretti
set_permissions() {
    local USER_HOME=$(get_user_home)
    
    if [ -n "$SUDO_USER" ]; then
        echo "Impostazione dei permessi per $SUDO_USER..."
        chown -R "$SUDO_USER:$SUDO_USER" "$USER_HOME/jellyfin" "$USER_HOME/portainer"
    fi
}

# Funzione principale
main() {
    check_root
    
    echo "Aggiornamento del sistema..."
    dnf upgrade -y
    
    install_base_packages
    install_docker
    setup_jellyfin
    setup_portainer
    set_permissions
    
    echo "Applicazione delle regole del firewall..."
    firewall-cmd --reload
    
    echo "Installazione completata!"
    echo "Per accedere a:"
    echo "- Cockpit: https://$(hostname -I | awk '{print $1}'):9090"
    echo "- Jellyfin: http://$(hostname -I | awk '{print $1}'):8096"
    echo "- Portainer: http://$(hostname -I | awk '{print $1}'):9000"
    echo ""
    echo "Si consiglia un riavvio del sistema per applicare tutte le modifiche."
    echo "Eseguire: sudo reboot"
}

main
