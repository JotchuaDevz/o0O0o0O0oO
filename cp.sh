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
# Pregunta sobre instalación de SSHPLUS
# ==========================================
echo -e "${C_YELLOW}[!] Es RECOMENDABLE instalar el script SSHPLUS para mayor funcionalidad.${C_RESET}"
echo -e -n "${C_MAGENTA}¿Deseas instalar SSHPLUS ahora? (Y/y/Si/si/N/n/No/no): ${C_RESET}"
read -r RESPONSE

case "$RESPONSE" in
    Y|y|Si|si|SI|Sí)
        echo -e "${C_GREEN}[✔] Instalando SSHPLUS...${C_RESET}\n"
        ;;
    N|n|No|no|NO)
        echo -e "${C_YELLOW}[!] Instalación de SSHPLUS cancelada.${C_RESET}"
        echo -e "${C_GREEN}[✔] Setup de DevzZJT completado.${C_RESET}"
        exit 0
        ;;
    *)
        echo -e "${C_RED}[!] Respuesta no válida. Solo se aceptan: Y/y/Si/si/N/n/No/no${C_RESET}"
        echo -e "${C_YELLOW}[!] Instalación de SSHPLUS cancelada.${C_RESET}"
        echo -e "${C_GREEN}[✔] Setup de DevzZJT completado.${C_RESET}"
        exit 0
        ;;
esac

echo -e "${C_CYAN}====================================================${C_RESET}"
echo -e "${C_YELLOW}🚀 Iniciando instalación de dependencias y SSHPLUS...${C_RESET}"
echo -e "${C_CYAN}====================================================${C_RESET}"

sleep 2

echo -e "${C_CYAN}[*] Actualizando repositorios del sistema (apt update & upgrade)...${C_RESET}"
apt update -y && apt upgrade -y

echo -e "\n${C_CYAN}[*] Descargando script Plus...${C_RESET}"
wget https://raw.githubusercontent.com/kiritosshxd/SSHPLUS/master/Plus

echo -e "\n${C_CYAN}[*] Dando permisos de ejecución y lanzando Plus...${C_RESET}"
chmod 777 Plus

# Fix Python mejorado para Ubuntu 22+
if [[ "$UBUNTU_VERSION" -ge 22 ]]; then
    echo -e "\n${C_CYAN}[*] Aplicando Fix Python Ubuntu 22+...${C_RESET}"
    if ! command -v python2.7 &>/dev/null; then
        echo -e "${C_YELLOW}[!] Python 2.7 no encontrado. Instalando...${C_RESET}"
        apt install -y python2.7 || echo -e "${C_RED}[!] No se pudo instalar Python 2.7.${C_RESET}"
    fi
    if ! command -v python &>/dev/null; then
        if command -v python2.7 &>/dev/null; then
            ln -sf /usr/bin/python2.7 /usr/bin/python
            echo -e "${C_GREEN}✅ Enlace python -> python2.7 creado.${C_RESET}"
        elif command -v python3 &>/dev/null; then
            ln -sf /usr/bin/python3 /usr/bin/python
            echo -e "${C_YELLOW}⚠️  Usando python3 como alternativa.${C_RESET}"
        else
            echo -e "${C_RED}[!] No se encontró Python.${C_RESET}"
        fi
    else
        echo -e "${C_GREEN}✅ Python ya está configurado.${C_RESET}"
    fi
fi

./Plus

echo -e "\n${C_GREEN}[✔] Setup de DevzZJT completado.${C_RESET}"
