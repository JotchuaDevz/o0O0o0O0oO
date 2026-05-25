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
echo -e "${C_MAGENTA}           WakkoDev Setup         ${C_RESET}"
echo -e "${C_CYAN}====================================================${C_RESET}"
echo ""

# --- Validación de Sistema Operativo ---
source /etc/os-release
if [[ "$ID" != "ubuntu" || "$VERSION_ID" != 20.* ]]; then
    echo -e "${C_RED}[!] ERROR: Este script solo es compatible con Ubuntu 20.x${C_RESET}"
    echo -e "${C_RED}[!] Tu sistema actual es: $PRETTY_NAME${C_RESET}"
    echo -e "${C_YELLOW}Instalación cancelada.${C_RESET}"
    exit 1
fi

echo -e "${C_GREEN}[✔] Sistema verificado: $PRETTY_NAME${C_RESET}\n"

# --- Petición de contraseña ---
echo -e "${C_YELLOW}[!] Vamos a configurar la autenticación PAM.${C_RESET}"
echo -e -n "${C_GREEN}🔑 Ingresa la Contraseña para el script: ${C_RESET}"
read PASSWORD
echo ""

# --- Paso 1: Crear el script de verificación ---
echo -e "${C_CYAN}[*] Generando archivo /usr/local/bin/verify_local.sh...${C_RESET}"

cat <<EOF >/usr/local/bin/verify_local.sh
#!/bin/bash
PASSWORD="$PASSWORD"
LOG="/tmp/pam_debug.log"

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

if (( now - timestamp > 60 )); then
    echo "timestamp expired" >> "\$LOG"
    exit 1
fi

expected=\$(printf "%s:::%s" "\$plain" "\$timestamp" | openssl dgst -sha256 -hmac "\$PASSWORD" | awk '{print \$2}')

echo "expected=\$expected" >> "\$LOG"

if [[ "\$expected" == "\$signature" ]]; then
    echo "OK" >> "\$LOG"
    exit 0
else
    echo "FAIL" >> "\$LOG"
    exit 1
fi
EOF

chmod 700 /usr/local/bin/verify_local.sh
chown root:root /usr/local/bin/verify_local.sh
echo -e "${C_GREEN}✅ Script de verificación creado e instalado.${C_RESET}\n"

# --- Paso 2: Editar archivo PAM y Reiniciar SSH ---
echo -e "${C_CYAN}[*] Configurando PAM en /etc/pam.d/sshd...${C_RESET}"
# Respaldar por seguridad
cp /etc/pam.d/sshd /etc/pam.d/sshd.bak
# Insertar la regla de autenticación en la línea 1 del archivo
sed -i '1i auth required pam_exec.so expose_authtok /usr/local/bin/verify_local.sh' /etc/pam.d/sshd
echo -e "${C_GREEN}✅ Archivo PAM modificado correctamente.${C_RESET}"

echo -e "${C_CYAN}[*] Reiniciando el servicio SSH...${C_RESET}"
systemctl restart ssh
echo -e "${C_GREEN}✅ Servicio SSH reiniciado.${C_RESET}\n"

# ==========================================
# Ejecución del segundo script (SSHPLUS)
# ==========================================
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
./Plus
