#!/bin/bash
C_CYAN="\e[96m"
C_GREEN="\e[92m"
C_YELLOW="\e[93m"
C_RED="\e[91m"
C_MAGENTA="\e[95m"
C_RESET="\e[0m"

clear
echo -e "${C_CYAN}====================================================${C_RESET}"
echo -e "${C_MAGENTA}  _      __      __    __         ${C_RESET}"
echo -e "${C_MAGENTA} | | /| / /__ _ / /__ / /__  ___  ${C_RESET}"
echo -e "${C_MAGENTA} | |/ |/ / _ \`/  '_//  '_/ / _ \\ ${C_RESET}"
echo -e "${C_MAGENTA} |__/|__/\\_,_//_/\\_\\/_/\\_\\ \\___/ ${C_RESET}"
echo -e "${C_MAGENTA}           DevzZJT Setup         ${C_RESET}"
echo -e "${C_CYAN}====================================================${C_RESET}"
echo ""

source /etc/os-release
UBUNTU_VERSION=$(echo "$VERSION_ID" | cut -d. -f1)

if [[ "$ID" != "ubuntu" || "$UBUNTU_VERSION" -lt 20 ]]; then
    echo -e "${C_RED}[!] ERROR: Este script solo es compatible con Ubuntu 20 LTS o superior${C_RESET}"
    echo -e "${C_RED}[!] Tu sistema actual es: $PRETTY_NAME${C_RESET}"
    echo -e "${C_YELLOW}Instalación cancelada.${C_RESET}"
    exit 1
fi

echo -e "${C_GREEN}[✔] Sistema verificado: $PRETTY_NAME${C_RESET}\n"

# ==========================================
# Detección y desactivación de UFW
# ==========================================
echo -e "${C_CYAN}[*] Verificando estado de UFW...${C_RESET}"
if command -v ufw &>/dev/null; then
    UFW_STATUS=$(ufw status | head -n1)
    if echo "$UFW_STATUS" | grep -qiw "active"; then
        echo -e "${C_YELLOW}[!] UFW está instalado y ACTIVO. Desactivando...${C_RESET}"
        ufw disable
        echo -e "${C_GREEN}✅ UFW desactivado correctamente.${C_RESET}\n"
    else
        echo -e "${C_GREEN}[✔] UFW está instalado pero inactivo. No se requiere acción.${C_RESET}\n"
    fi
else
    echo -e "${C_YELLOW}[!] UFW no está instalado. Instalando...${C_RESET}"
    apt install -y ufw
    echo -e "${C_YELLOW}[!] Desactivando UFW recién instalado...${C_RESET}"
    ufw disable
    echo -e "${C_GREEN}✅ UFW instalado y desactivado.${C_RESET}\n"
fi

# Instalar dependencias
echo -e "${C_CYAN}[*] Verificando dependencias...${C_RESET}"
for pkg in openssl wget curl; do
    if ! command -v $pkg &>/dev/null; then
        echo -e "${C_YELLOW}[!] Instalando $pkg...${C_RESET}"
        apt install -y $pkg
    fi
done

echo -e "${C_YELLOW}[!] Vamos a configurar la autenticación PAM.${C_RESET}"
echo -e -n "${C_GREEN}🔑 Ingresa la Contraseña para el script: ${C_RESET}"
read PASSWORD
echo ""

echo -e "${C_CYAN}[*] Generando archivo /usr/local/bin/verify_local.sh...${C_RESET}"

cat <<EOF >/usr/local/bin/verify_local.sh
#!/bin/bash
# Script PAM con token (compatible Ubuntu 20, 22, 24+)
PASSWORD="$PASSWORD"
LOG="/tmp/pam_debug.log"
TIMEOUT=300  # 5 minutos de margen

ALLOWED_USERS=("root")

for allowed in "\${ALLOWED_USERS[@]}"; do
    if [[ "\$PAM_USER" == "\$allowed" ]]; then
        echo "[\$(date)] Usuario permitido sin autenticación PAM: \$PAM_USER" >> "\$LOG"
        exit 0
    fi
done

read input
plain=\$(echo "\$input" | cut -d':' -f1)
timestamp=\$(echo "\$input" | cut -d':' -f4)
signature=\$(echo "\$input" | cut -d':' -f7)

now=\$(date +%s)
echo "[\$(date)] PAM_USER=\$PAM_USER input=\$input" >> "\$LOG"
echo "plain=\$plain timestamp=\$timestamp signature=\$signature" >> "\$LOG"

# Verificar timestamp con margen ampliado
if (( now - timestamp > TIMEOUT || timestamp - now > TIMEOUT )); then
    echo "timestamp expired (now=\$now, timestamp=\$timestamp)" >> "\$LOG"
    exit 1
fi

expected=\$(printf "%s:::%s" "\$plain" "\$timestamp" | openssl dgst -sha256 -hmac "\$PASSWORD" | awk '{print \$2}')

echo "expected=\$expected" >> "\$LOG"

if [[ "\$expected" == "\$signature" ]]; then
    echo "OK (token)" >> "\$LOG"
    exit 0
else
    echo "FAIL (token)" >> "\$LOG"
    exit 1
fi
EOF

chmod 700 /usr/local/bin/verify_local.sh
chown root:root /usr/local/bin/verify_local.sh
echo -e "${C_GREEN}✅ Script de verificación creado e instalado.${C_RESET}\n"

echo -e "${C_CYAN}[*] Configurando PAM en /etc/pam.d/sshd...${C_RESET}"
cp /etc/pam.d/sshd /etc/pam.d/sshd.bak

# Añadir nuestras líneas al principio del archivo
sed -i '1i auth required pam_exec.so expose_authtok /usr/local/bin/verify_local.sh' /etc/pam.d/sshd
sed -i '2i auth required pam_permit.so' /etc/pam.d/sshd

# Comentar common-auth para evitar que pida contraseña del sistema
sed -i 's/^@include common-auth/#@include common-auth/' /etc/pam.d/sshd

echo -e "${C_GREEN}✅ Archivo PAM modificado correctamente.${C_RESET}"

echo -e "${C_CYAN}[*] Reiniciando el servicio SSH...${C_RESET}"
systemctl restart ssh 2>/dev/null || systemctl restart sshd
echo -e "${C_GREEN}✅ Servicio SSH reiniciado.${C_RESET}\n"

echo -e "${C_CYAN}====================================================${C_RESET}"
echo -e "${C_GREEN}✅ Configuración de PAM completada exitosamente.${C_RESET}"
echo -e "${C_CYAN}====================================================${C_RESET}\n"

# ==========================================
# Pregunta sobre instalación de UDP
# ==========================================
echo -e "${C_YELLOW}[!] Es RECOMENDABLE instalar el script UDP para mayor funcionalidad.${C_RESET}"
echo -e -n "${C_MAGENTA}¿Deseas instalar el script UDP ahora? (Y/y/Si/si/N/n/No/no): ${C_RESET}"
read -r RESPONSE_UDP

case "$RESPONSE_UDP" in
    Y|y|Si|si|SI|Sí)
        echo -e "${C_CYAN}====================================================${C_RESET}"
        echo -e "${C_YELLOW}🚀 Iniciando instalación del script UDP...${C_RESET}"
        echo -e "${C_CYAN}====================================================${C_RESET}"
        sleep 1
        curl -sL https://raw.githubusercontent.com/hahacrunchyrollls/TFN-UDP/refs/heads/main/install | bash
        echo -e "${C_GREEN}✅ Script UDP instalado.${C_RESET}\n"
        ;;
    N|n|No|no|NO)
        echo -e "${C_YELLOW}[!] Instalación de UDP cancelada.${C_RESET}\n"
        ;;
    *)
        echo -e "${C_RED}[!] Respuesta no válida. Instalación de UDP cancelada.${C_RESET}\n"
        ;;
esac

# ==========================================
# Pregunta sobre instalación de un script Plus
# ==========================================
echo -e "${C_YELLOW}[!] Es RECOMENDABLE instalar un script Plus para mayor funcionalidad.${C_RESET}"
echo -e -n "${C_MAGENTA}¿Deseas instalar un script Plus ahora? (Y/y/Si/si/N/n/No/no): ${C_RESET}"
read -r RESPONSE

case "$RESPONSE" in
    Y|y|Si|si|SI|Sí)
        ;;
    N|n|No|no|NO)
        echo -e "${C_YELLOW}[!] Instalación cancelada.${C_RESET}"
        echo -e "${C_GREEN}[✔] Setup de DevzZJT completado.${C_RESET}"
        exit 0
        ;;
    *)
        echo -e "${C_RED}[!] Respuesta no válida. Instalación cancelada.${C_RESET}"
        echo -e "${C_GREEN}[✔] Setup de DevzZJT completado.${C_RESET}"
        exit 0
        ;;
esac

echo -e "${C_CYAN}====================================================${C_RESET}"
echo -e "${C_MAGENTA}      Selecciona el instalador que deseas usar:${C_RESET}"
echo -e "${C_CYAN}====================================================${C_RESET}"
echo -e "${C_GREEN}1.${C_RESET} Hex Tunnel Script By JotchuaDevz"
echo -e "${C_GREEN}2.${C_RESET} SSHPLUS Español"
echo -e "${C_GREEN}3.${C_RESET} Darnix Script (Requiere Key y Subdominio)"
echo -e "${C_GREEN}4.${C_RESET} Omitir y finalizar instalación"
echo -e -n "${C_MAGENTA}Opción: ${C_RESET}"
read -r OPCION_INSTALLER

case "$OPCION_INSTALLER" in
    1)
        echo -e "${C_CYAN}====================================================${C_RESET}"
        echo -e "${C_YELLOW}🚀 Iniciando instalación de dependencias y Hex Tunnel Script By JotchuaDevz...${C_RESET}"
        echo -e "${C_CYAN}====================================================${C_RESET}"
        sleep 2

        echo -e "${C_CYAN}[*] Actualizando repositorios del sistema (apt update & upgrade)...${C_RESET}"
        apt update -y && apt upgrade -y

        echo -e "\n${C_CYAN}[*] Descargando script...${C_RESET}"
        wget -qO install.sh https://raw.githubusercontent.com/JotchuaDevz/Porno-OS/refs/heads/main/install.sh
        chmod +x install.sh
        ./install.sh
        ;;
    2)
        echo -e "${C_CYAN}====================================================${C_RESET}"
        echo -e "${C_YELLOW}🚀 Iniciando instalación de SSHPLUS Español...${C_RESET}"
        echo -e "${C_CYAN}====================================================${C_RESET}"
        sleep 2
        wget -qO ssh-plus https://raw.githubusercontent.com/Davidgelves/ssh-pro-vpn/main/ssh-plus && chmod +x ssh-plus && bash ssh-plus
        ;;
    3)
        echo -e "${C_CYAN}====================================================${C_RESET}"
        echo -e "${C_YELLOW}🚀 Iniciando instalación de Darnix Script...${C_RESET}"
        echo -e "${C_RED}[!] Este script requiere Key y Subdominio.${C_RESET}"
        echo -e "${C_CYAN}====================================================${C_RESET}"
        sleep 2
        wget -4 -O setup https://raw.githubusercontent.com/darnix0/darnix/refs/heads/mein/setup && chmod +x setup && sudo ./setup
        ;;
    4)
        echo -e "${C_YELLOW}[!] Omitiendo instalación de script Plus.${C_RESET}"
        ;;
    *)
        echo -e "${C_RED}[!] Opción no válida. Cancelando instalación del script Plus.${C_RESET}"
        ;;
esac

echo -e "\n${C_GREEN}[✔] Setup de DevzZJT completado.${C_RESET}"
