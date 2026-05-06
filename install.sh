#!/bin/bash

# ─── Colores ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Verificar root ───
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Ejecuta como root.${NC}"
    exit 1
fi

# ─── Instalar comando global ───
if ! command -v wakkossh &>/dev/null; then
    cp "$0" /usr/local/bin/wakkossh
    chmod +x /usr/local/bin/wakkossh
    echo -e "${GREEN}  ✔ Comando 'wakkossh' instalado. Usa 'wakkossh' para volver al menú.${NC}"
    sleep 1
fi

# ─── Animación de instalación ───
animacion_instalacion() {
    clear
    echo -e "${CYAN}"
    echo "  ██╗    ██╗ █████╗ ██╗  ██╗██╗  ██╗ ██████╗ "
    echo "  ██║    ██║██╔══██╗██║ ██╔╝██║ ██╔╝██╔═══██╗"
    echo "  ██║ █╗ ██║███████║█████╔╝ █████╔╝ ██║   ██║"
    echo "  ██║███╗██║██╔══██║██╔═██╗ ██╔═██╗ ██║   ██║"
    echo "  ╚███╔███╔╝██║  ██║██║  ██╗██║  ██╗╚██████╔╝"
    echo "   ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ "
    echo -e "${NC}"
    echo -e "${MAGENTA}         SSH Key Manager by WakkoDev${NC}"
    echo -e "${YELLOW}         ================================${NC}"
    echo ""
    sleep 1

    PASOS=(
        "Verificando dependencias del sistema"
        "Comprobando configuración SSH"
        "Cargando módulos de cifrado"
        "Inicializando gestor de usuarios"
        "Preparando entorno seguro"
    )

    for PASO in "${PASOS[@]}"; do
        echo -ne "${CYAN}  [ ${NC}${YELLOW}....${NC}${CYAN} ]${NC} $PASO"
        sleep 0.4
        echo -e "\r${CYAN}  [ ${NC}${GREEN} OK ${NC}${CYAN} ]${NC} $PASO"
    done

    echo ""
    echo -e "${GREEN}  ✔ Sistema listo.${NC}"
    sleep 1
}

# ─── Reiniciar SSH ───
reiniciar_ssh() {
    echo -ne "  ${CYAN}[ .... ]${NC} Reiniciando SSH..."
    if command -v dropbear &>/dev/null; then
        service dropbear restart 2>/dev/null
        systemctl restart dropbear 2>/dev/null
    fi
    service ssh restart 2>/dev/null
    service sshd restart 2>/dev/null
    echo -e "\r  ${GREEN}[  OK  ]${NC} SSH reiniciado"
}

# ─── Menú principal ───
mostrar_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}${MAGENTA}SSH KEY MANAGER${NC} ${CYAN}─ WakkoDev        ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}1.${NC} Generar nueva llave SSH           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}2.${NC} Agregar usuario SSH               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}3.${NC} Eliminar llave de usuario         ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}4.${NC} Listar llaves autorizadas         ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}5.${NC} Configurar SSHD                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}6.${NC} Configurar Dropbear               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${RED}7.${NC} Salir                             ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
    echo -ne "  Opción: "
    read OPCION
}

# ─── Generar llave ───
generar_llave() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}       ${BOLD}GENERAR NUEVA LLAVE SSH${NC}        ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
    echo ""

    read -p "  Nombre del archivo de llave: " NOMBRE_LLAVE
    read -p "  Usuario SSH (debe existir):  " USUARIO

    if ! id "$USUARIO" &>/dev/null; then
        echo -e "${RED}  ✘ El usuario '$USUARIO' no existe.${NC}"
        read -p "  Presiona Enter para continuar..."
        return
    fi

    read -s -p "  Passphrase: " PASSPHRASE1; echo
    read -s -p "  Confirma passphrase: " PASSPHRASE2; echo

    if [[ "$PASSPHRASE1" != "$PASSPHRASE2" ]]; then
        echo -e "${RED}  ✘ Los passphrases no coinciden.${NC}"
        read -p "  Presiona Enter para continuar..."
        return
    fi

    if [[ -z "$PASSPHRASE1" ]]; then
        echo -e "${RED}  ✘ El passphrase no puede estar vacío.${NC}"
        read -p "  Presiona Enter para continuar..."
        return
    fi

    IP_SERVIDOR=$(hostname -I | awk '{print $1}')
    SSH_DIR="/home/$USUARIO/.ssh"
    mkdir -p "$SSH_DIR"
    chown "$USUARIO:$USUARIO" "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    KEY_PATH="$SSH_DIR/$NOMBRE_LLAVE"

    echo ""
    echo -ne "  ${CYAN}[ .... ]${NC} Generando llave ed25519..."
    ssh-keygen -t ed25519 -f "$KEY_PATH" -N "$PASSPHRASE1" &>/dev/null
    echo -e "\r  ${GREEN}[  OK  ]${NC} Llave generada"

    read -s -p "  Contraseña AES para cifrar clave privada: " AES_PASS; echo

    echo -ne "  ${CYAN}[ .... ]${NC} Cifrando clave privada..."
    openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt \
        -in "$KEY_PATH" -out "$KEY_PATH.enc" -k "$AES_PASS" 2>/dev/null
    echo -n "WakkoDev" | dd of="$KEY_PATH.enc" bs=1 count=8 conv=notrunc status=none
    echo -e "\r  ${GREEN}[  OK  ]${NC} Clave cifrada con AES-256"

    echo -ne "  ${CYAN}[ .... ]${NC} Eliminando clave original..."
    shred -u "$KEY_PATH"
    echo -e "\r  ${GREEN}[  OK  ]${NC} Clave original eliminada"

    echo -ne "  ${CYAN}[ .... ]${NC} Autorizando llave pública..."
    cat "$KEY_PATH.pub" >> "$SSH_DIR/authorized_keys"
    chmod 600 "$SSH_DIR/authorized_keys"
    chown "$USUARIO:$USUARIO" "$SSH_DIR/authorized_keys"
    echo -e "\r  ${GREEN}[  OK  ]${NC} Llave pública autorizada"

    echo ""
    echo -e "${GREEN}  ╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}  ║      LLAVE GENERADA EXITOSAMENTE     ║${NC}"
    echo -e "${GREEN}  ╠══════════════════════════════════════╣${NC}"
    echo -e "${GREEN}  ║${NC} Usuario:       $USUARIO"
    echo -e "${GREEN}  ║${NC} IP servidor:   $IP_SERVIDOR"
    echo -e "${GREEN}  ║${NC} Clave cifrada: $KEY_PATH.enc"
    echo -e "${GREEN}  ║${NC} Clave pública: $KEY_PATH.pub"
    echo -e "${GREEN}  ╚══════════════════════════════════════╝${NC}"
    read -p "  Presiona Enter para continuar..."
}

# ─── Agregar usuario ───
agregar_usuario() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}         ${BOLD}AGREGAR USUARIO SSH${NC}           ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
    echo ""

    read -p "  Nombre del nuevo usuario: " NUEVO_USUARIO

    if id "$NUEVO_USUARIO" &>/dev/null; then
        echo -e "${YELLOW}  ⚠ El usuario '$NUEVO_USUARIO' ya existe.${NC}"
        read -p "  Presiona Enter para continuar..."
        return
    fi

    read -s -p "  Contraseña para $NUEVO_USUARIO: " PASS; echo

    echo -ne "  ${CYAN}[ .... ]${NC} Creando usuario..."
    useradd -m -s /bin/bash "$NUEVO_USUARIO"
    echo "$NUEVO_USUARIO:$PASS" | chpasswd
    echo -e "\r  ${GREEN}[  OK  ]${NC} Usuario creado"

    echo -ne "  ${CYAN}[ .... ]${NC} Configurando directorio SSH..."
    SSH_DIR="/home/$NUEVO_USUARIO/.ssh"
    mkdir -p "$SSH_DIR"
    chown "$NUEVO_USUARIO:$NUEVO_USUARIO" "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    touch "$SSH_DIR/authorized_keys"
    chmod 600 "$SSH_DIR/authorized_keys"
    chown "$NUEVO_USUARIO:$NUEVO_USUARIO" "$SSH_DIR/authorized_keys"
    echo -e "\r  ${GREEN}[  OK  ]${NC} Directorio SSH configurado"

    echo -ne "  ${CYAN}[ .... ]${NC} Forzando autenticación solo por llave..."
    SSHD_CONFIG="/etc/ssh/sshd_config"
    if ! grep -q "Match User $NUEVO_USUARIO" "$SSHD_CONFIG"; then
        cat >> "$SSHD_CONFIG" <<EOF

# Solo llave SSH para $NUEVO_USUARIO
Match User $NUEVO_USUARIO
    PasswordAuthentication no
    PubkeyAuthentication yes
EOF
    fi
    echo -e "\r  ${GREEN}[  OK  ]${NC} Usuario restringido a solo llave SSH"

    reiniciar_ssh

    echo ""
    echo -e "${GREEN}  ✔ Usuario '$NUEVO_USUARIO' listo. Solo acepta llave SSH.${NC}"
    read -p "  Presiona Enter para continuar..."
}

# ─── Eliminar llave ───
eliminar_llave() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}       ${BOLD}ELIMINAR LLAVE DE USUARIO${NC}       ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
    echo ""

    read -p "  Usuario: " USUARIO

    if ! id "$USUARIO" &>/dev/null; then
        echo -e "${RED}  ✘ El usuario '$USUARIO' no existe.${NC}"
        read -p "  Presiona Enter para continuar..."
        return
    fi

    SSH_DIR="/home/$USUARIO/.ssh"
    AUTH_KEYS="$SSH_DIR/authorized_keys"

    if [ ! -f "$AUTH_KEYS" ] || [ ! -s "$AUTH_KEYS" ]; then
        echo -e "${YELLOW}  ⚠ No hay llaves autorizadas para '$USUARIO'.${NC}"
        read -p "  Presiona Enter para continuar..."
        return
    fi

    echo -e "${YELLOW}  Llaves actuales de $USUARIO:${NC}"
    cat -n "$AUTH_KEYS"
    echo ""
    read -p "  Número de llave a eliminar (0 = todas): " NUM

    if [[ "$NUM" == "0" ]]; then
        > "$AUTH_KEYS"
        echo -e "${GREEN}  ✔ Todas las llaves eliminadas.${NC}"
    else
        sed -i "${NUM}d" "$AUTH_KEYS"
        echo -e "${GREEN}  ✔ Llave $NUM eliminada.${NC}"
    fi

    read -p "  ¿Eliminar archivos .enc y .pub? (s/n): " RESP
    if [[ "$RESP" == "s" ]]; then
        read -p "  Nombre del archivo de llave: " NOMBRE_LLAVE
        KEY_PATH="$SSH_DIR/$NOMBRE_LLAVE"
        [ -f "$KEY_PATH.enc" ] && shred -u "$KEY_PATH.enc" && echo -e "${GREEN}  ✔ Eliminado: $KEY_PATH.enc${NC}"
        [ -f "$KEY_PATH.pub" ] && rm "$KEY_PATH.pub" && echo -e "${GREEN}  ✔ Eliminado: $KEY_PATH.pub${NC}"
    fi

    sed -i "/# Solo llave SSH para $USUARIO/{N;N;N;d}" /etc/ssh/sshd_config
    reiniciar_ssh

    read -p "  Presiona Enter para continuar..."
}

# ─── Listar llaves ───
listar_llaves() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}      ${BOLD}LLAVES AUTORIZADAS POR USUARIO${NC}    ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
    echo ""

    ENCONTRADO=false
    for HOME_DIR in /home/*/; do
        USUARIO=$(basename "$HOME_DIR")
        AUTH_KEYS="$HOME_DIR.ssh/authorized_keys"
        if [ -f "$AUTH_KEYS" ] && [ -s "$AUTH_KEYS" ]; then
            ENCONTRADO=true
            echo -e "${YELLOW}  ── $USUARIO ──${NC}"
            cat -n "$AUTH_KEYS"
            echo ""
        fi
    done

    if [ "$ENCONTRADO" = false ]; then
        echo -e "${YELLOW}  ⚠ No hay llaves autorizadas en ningún usuario.${NC}"
    fi

    read -p "  Presiona Enter para continuar..."
}

# ─── Configurar SSHD ───
configurar_ssh() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}          ${BOLD}CONFIGURAR SSHD${NC}               ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
    echo ""

    SSHD_CONFIG="/etc/ssh/sshd_config"
    CLOUDIMG_CONF="/etc/ssh/sshd_config.d/60-cloudimg-settings.conf"
    CLOUD_INIT_CONF="/etc/ssh/sshd_config.d/50-cloud-init.conf"

    echo -ne "  ${CYAN}[ .... ]${NC} Deshabilitando password global..."
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
    sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
    echo -e "\r  ${GREEN}[  OK  ]${NC} Password global deshabilitado"

    for CONF in "$CLOUDIMG_CONF" "$CLOUD_INIT_CONF"; do
        if [ -f "$CONF" ]; then
            echo -ne "  ${CYAN}[ .... ]${NC} Parcheando $CONF..."
            sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$CONF"
            echo -e "\r  ${GREEN}[  OK  ]${NC} Parcheado: $CONF"
        fi
    done

    echo -ne "  ${CYAN}[ .... ]${NC} Configurando acceso root con password..."
    if ! grep -q "Match User root" "$SSHD_CONFIG"; then
        cat >> "$SSHD_CONFIG" <<EOF

# Permitir password solo para root
Match User root
    PasswordAuthentication yes
    PubkeyAuthentication no
EOF
        echo -e "\r  ${GREEN}[  OK  ]${NC} Bloque root agregado"
    else
        echo -e "\r  ${YELLOW}[  --  ]${NC} Bloque root ya existe"
    fi

    reiniciar_ssh

    echo ""
    echo -e "${GREEN}  ✔ SSHD configurado correctamente.${NC}"
    read -p "  Presiona Enter para continuar..."
}

# ─── Configurar Dropbear ───
configurar_dropbear() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}        ${BOLD}CONFIGURAR DROPBEAR${NC}            ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
    echo ""

    DROPBEAR_CONF="/etc/default/dropbear"

    if [ ! -f "$DROPBEAR_CONF" ]; then
        echo -e "${RED}  ✘ Dropbear no está instalado o no se encontró config.${NC}"
        read -p "  Presiona Enter para continuar..."
        return
    fi

    echo -ne "  ${CYAN}[ .... ]${NC} Deshabilitando password, forzando solo llave..."
    if grep -q "DROPBEAR_EXTRA_ARGS" "$DROPBEAR_CONF"; then
        sed -i 's/^DROPBEAR_EXTRA_ARGS=.*/DROPBEAR_EXTRA_ARGS="-s -g"/' "$DROPBEAR_CONF"
    else
        echo 'DROPBEAR_EXTRA_ARGS="-s -g"' >> "$DROPBEAR_CONF"
    fi
    echo -e "\r  ${GREEN}[  OK  ]${NC} Password deshabilitado, solo llave SSH permitida"

    echo -ne "  ${CYAN}[ .... ]${NC} Reiniciando Dropbear..."
    service dropbear restart 2>/dev/null
    systemctl restart dropbear 2>/dev/null
    echo -e "\r  ${GREEN}[  OK  ]${NC} Dropbear reiniciado"

    echo ""
    echo -e "${YELLOW}  Flags aplicados:${NC}"
    echo -e "  ${GREEN}-s${NC} → Deshabilita login con password"
    echo -e "  ${GREEN}-g${NC} → Deshabilita login de root con password"
    echo -e "${GREEN}  ✔ Solo llave privada permitida para todos los usuarios.${NC}"
    read -p "  Presiona Enter para continuar..."
}

# ─── Inicio ───
animacion_instalacion

while true; do
    mostrar_menu
    case $OPCION in
        1) generar_llave ;;
        2) agregar_usuario ;;
        3) eliminar_llave ;;
        4) listar_llaves ;;
        5) configurar_ssh ;;
        6) configurar_dropbear ;;
        7) echo -e "${GREEN}  Saliendo...${NC}"; exit 0 ;;
        *) echo -e "${RED}  ✘ Opción inválida.${NC}"; sleep 1 ;;
    esac
done
