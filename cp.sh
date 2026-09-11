#!/bin/bash
C_CYAN="\e[96m"
C_GREEN="\e[92m"
C_YELLOW="\e[93m"
C_RED="\e[91m"
C_MAGENTA="\e[95m"
C_RESET="\e[0m"

clear
echo -e "${C_CYAN}====================================================${C_RESET}"
echo -e "${C_MAGENTA}     _       _            _             ${C_RESET}"
echo -e "${C_MAGENTA}    | | ___ | |_  ___  __| |_   _  __ _ ${C_RESET}"
echo -e "${C_MAGENTA} _  | |/ _ \\| __|/ __|/ _\` | | | |/ _\` |${C_RESET}"
echo -e "${C_MAGENTA}| |_| | (_) | |_| (__| (_| | |_| | (_| |${C_RESET}"
echo -e "${C_MAGENTA} \\___/ \\___/ \\__|\\___|\\__,_|\\__,_|\\__,_|${C_RESET}"
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

if [[ $EUID -ne 0 ]]; then
    echo -e "${C_RED}[!] Este script debe ejecutarse como root.${C_RESET}"
    exit 1
fi

cat >/usr/local/bin/pam_rescue.sh <<'RESCUE_EOF'
#!/bin/bash
set -e
BACKUP=$(ls -t /etc/pam.d/sshd.bak* 2>/dev/null | head -n1)
if [[ -z "$BACKUP" ]]; then
    echo "[!] No hay backup disponible en /etc/pam.d/"
    exit 1
fi
cp "$BACKUP" /etc/pam.d/sshd
systemctl restart ssh 2>/dev/null || systemctl restart sshd
echo "[✔] Configuración PAM restaurada desde $BACKUP"
RESCUE_EOF

chmod 700 /usr/local/bin/pam_rescue.sh
chown root:root /usr/local/bin/pam_rescue.sh

echo -e "${C_CYAN}[*] Verificando estado de UFW...${C_RESET}"
if command -v ufw &>/dev/null; then
    UFW_STATUS=$(ufw status | head -n1)
    if echo "$UFW_STATUS" | grep -qiw "active"; then
        echo -e "${C_YELLOW}[!] UFW está instalado y ACTIVO. Desactivando...${C_RESET}"
        ufw disable
        echo -e "${C_GREEN}✅ UFW desactivado correctamente.${C_RESET}\n"
    else
        echo -e "${C_GREEN}[✔] UFW está instalado pero inactivo.${C_RESET}\n"
    fi
else
    echo -e "${C_YELLOW}[!] UFW no está instalado. Instalando...${C_RESET}"
    apt update -y
    apt install -y ufw
    ufw disable
    echo -e "${C_GREEN}✅ UFW instalado y desactivado.${C_RESET}\n"
fi

echo -e "${C_CYAN}[*] Verificando dependencias...${C_RESET}"
for pkg in openssl wget curl; do
    if ! command -v $pkg &>/dev/null; then
        echo -e "${C_YELLOW}[!] Instalando $pkg...${C_RESET}"
        apt install -y $pkg
    fi
done

echo -e "${C_YELLOW}[!] Vamos a configurar la autenticación PAM.${C_RESET}"
echo -e -n "${C_GREEN}🔑 Ingresa la Contraseña para el script: ${C_RESET}"
read -r -s PASSWORD
echo ""

if [[ -z "$PASSWORD" ]]; then
    echo -e "${C_RED}[!] La contraseña no puede estar vacía. Abortando.${C_RESET}"
    exit 1
fi

ESCAPED_PASSWORD=$(printf '%s' "$PASSWORD" | sed 's/[\\"$`]/\\&/g')

echo -e "${C_CYAN}[*] Generando /usr/local/bin/verify_local.sh...${C_RESET}"

cat <<EOF >/usr/local/bin/verify_local.sh
#!/bin/bash
# ----------Jotchua----------
PASSWORD="$ESCAPED_PASSWORD"
LOG="/var/log/verify_local.log"

SAFE_USERS=("root" "ubuntu")

if [[ ! -f "\$LOG" ]]; then
    touch "\$LOG" && chmod 600 "\$LOG"
fi

if [[ -z "\$PAM_USER" ]]; then
    echo "[\$(date)] PAM_USER vacío, rechazando" >> "\$LOG"
    exit 1
fi

for safe in "\${SAFE_USERS[@]}"; do
    if [[ "\$PAM_USER" == "\$safe" ]]; then
        echo "[\$(date)] \$PAM_USER llegó al script, permitiendo por seguridad" >> "\$LOG"
        exit 0
    fi
done

read -r input
plain=\$(echo "\$input" | cut -d':' -f1)
timestamp=\$(echo "\$input" | cut -d':' -f4)
signature=\$(echo "\$input" | cut -d':' -f7)

now=\$(date +%s)
echo "[\$(date)] PAM_USER=\$PAM_USER timestamp=\$timestamp" >> "\$LOG"

if [[ -z "\$plain" || -z "\$timestamp" || -z "\$signature" ]]; then
    echo "[\$(date)] campos incompletos" >> "\$LOG"
    exit 1
fi

if (( now - timestamp > 60 )); then
    echo "[\$(date)] timestamp expired" >> "\$LOG"
    exit 1
fi

expected=\$(printf "%s:::%s" "\$plain" "\$timestamp" | openssl dgst -sha256 -hmac "\$PASSWORD" | awk '{print \$2}')

if [[ "\$expected" == "\$signature" ]]; then
    echo "[\$(date)] OK (token) para \$PAM_USER" >> "\$LOG"
    exit 0
else
    echo "[\$(date)] FAIL (token) para \$PAM_USER" >> "\$LOG"
    exit 1
fi
EOF

chmod 700 /usr/local/bin/verify_local.sh
chown root:root /usr/local/bin/verify_local.sh
echo -e "${C_GREEN}✅ Script de verificación creado.${C_RESET}\n"

echo -e "${C_CYAN}[*] Configurando PAM en /etc/pam.d/sshd...${C_RESET}"
BACKUP_FILE="/etc/pam.d/sshd.bak.$(date +%Y%m%d-%H%M%S)"
cp /etc/pam.d/sshd "$BACKUP_FILE"
echo -e "${C_GREEN}✅ Backup guardado en: $BACKUP_FILE${C_RESET}"

sed -i '/DevzZJT_PAM_START/,/DevzZJT_PAM_END/d' /etc/pam.d/sshd
sed -i '/verify_local\.sh/d' /etc/pam.d/sshd
sed -i '/^auth[[:space:]]\+required[[:space:]]\+pam_permit\.so/d' /etc/pam.d/sshd
sed -i 's/^@include common-auth/#@include common-auth/' /etc/pam.d/sshd
sed -i 's/^auth[[:space:]]\+required[[:space:]]\+pam_unix\.so/#auth required pam_unix.so/' /etc/pam.d/sshd

{
    echo "# DevzZJT_PAM_START"
    echo "auth [success=1 default=ignore] pam_succeed_if.so user in root:ubuntu"
    echo "auth required pam_exec.so expose_authtok /usr/local/bin/verify_local.sh"
    echo "auth [success=ok default=1] pam_succeed_if.so user in root:ubuntu"
    echo "auth required pam_unix.so"
    echo "# DevzZJT_PAM_END"
    cat /etc/pam.d/sshd
} > /etc/pam.d/sshd.tmp
mv /etc/pam.d/sshd.tmp /etc/pam.d/sshd

echo -e "${C_CYAN}[*] Validando configuración...${C_RESET}"

if ! sshd -t 2>/tmp/sshd_test.err; then
    echo -e "${C_RED}[!] Error de sintaxis en sshd:${C_RESET}"
    cat /tmp/sshd_test.err
    cp "$BACKUP_FILE" /etc/pam.d/sshd
    exit 1
fi

if ! bash -n /usr/local/bin/verify_local.sh; then
    echo -e "${C_RED}[!] verify_local.sh tiene errores de sintaxis. Restaurando...${C_RESET}"
    cp "$BACKUP_FILE" /etc/pam.d/sshd
    exit 1
fi

if ! grep -q 'pam_succeed_if.so user in root:ubuntu' /etc/pam.d/sshd; then
    echo -e "${C_RED}[!] Falta pam_succeed_if. Restaurando...${C_RESET}"
    cp "$BACKUP_FILE" /etc/pam.d/sshd
    exit 1
fi

echo -e "${C_GREEN}✅ Validación OK.${C_RESET}\n"

echo -e "${C_YELLOW}⚠️  NO cierres esta sesión SSH. Abre OTRA terminal y prueba conectarte como root y ubuntu.${C_RESET}"
echo -e "${C_YELLOW}    Si algo falla ejecuta: /usr/local/bin/pam_rescue.sh${C_RESET}"
echo ""
echo -e -n "${C_MAGENTA}¿Reiniciar SSH ahora? (s/n): ${C_RESET}"
read -r CONFIRM
if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" && "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo -e "${C_YELLOW}[!] Reinicio cancelado. Aplícalo luego con: systemctl restart ssh${C_RESET}"
    exit 0
fi

systemctl restart ssh 2>/dev/null || systemctl restart sshd
echo -e "${C_GREEN}✅ Servicio SSH reiniciado.${C_RESET}\n"

echo -e "${C_CYAN}====================================================${C_RESET}"
echo -e "${C_GREEN}✅ Configuración de PAM completada exitosamente.${C_RESET}"
echo -e "${C_CYAN}====================================================${C_RESET}\n"

echo -e "${C_GREEN}[✔] Setup de DevzZJT completado.${C_RESET}"
