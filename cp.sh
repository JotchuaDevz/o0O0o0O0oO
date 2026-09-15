#!/bin/bash
# =====================================================
#  DevzZJT Setup — Autenticación HMAC por usuario
#  root        → contraseña normal (pam_unix)
#  otros       → HMAC obligatorio (pam_exec)
# =====================================================

set -euo pipefail

# --- Colores ---
C_RED="\e[91m"
C_GREEN="\e[92m"
C_YELLOW="\e[93m"
C_BLUE="\e[94m"
C_MAGENTA="\e[95m"
C_CYAN="\e[96m"
C_RESET="\e[0m"

COLORS=(
    "\e[91m" "\e[92m" "\e[93m" "\e[94m" "\e[95m" "\e[96m"
    "\e[97m" "\e[38;5;208m" "\e[38;5;213m" "\e[38;5;45m"
    "\e[38;5;51m" "\e[38;5;118m" "\e[38;5;226m"
)
randcolor() { echo "${COLORS[$RANDOM % ${#COLORS[@]}]}"; }

clear
echo -e "$(randcolor)====================================================${C_RESET}"
echo -e "$(randcolor)  _      __      __    __                          ${C_RESET}"
echo -e "$(randcolor) | | /| / /__ _ / /__ / /__  ___                   ${C_RESET}"
echo -e "$(randcolor) | |/ |/ / _ \`/  '_//  '_/ / _ \\\\                 ${C_RESET}"
echo -e "$(randcolor) |__/|__/\\_,_//_/\\_\\/_/\\_\\\\ \\___/                ${C_RESET}"
echo -e "$(randcolor)             DevzZJT Setup                         ${C_RESET}"
echo -e "$(randcolor)====================================================${C_RESET}"
echo ""
echo -e "$(randcolor)▶ Iniciando instalación...${C_RESET}"
echo -e "$(randcolor)▶ Verificando dependencias...${C_RESET}"
echo -e "$(randcolor)▶ Configurando sistema...${C_RESET}"
echo ""

# --- Validación SO ---
source /etc/os-release
VERSION_MAJOR=$(echo "$VERSION_ID" | cut -d. -f1)

if [[ "$ID" == "ubuntu" ]]; then
    (( VERSION_MAJOR < 20 )) && { echo -e "${C_RED}[!] ERROR: Ubuntu 20 o superior requerido${C_RESET}"; exit 1; }
elif [[ "$ID" == "debian" ]]; then
    (( VERSION_MAJOR < 11 )) && { echo -e "${C_RED}[!] ERROR: Debian 11 o superior requerido${C_RESET}"; exit 1; }
else
    echo -e "${C_RED}[!] ERROR: Solo Ubuntu o Debian${C_RESET}"; exit 1
fi

echo -e "${C_GREEN}[✔] Sistema verificado: $PRETTY_NAME${C_RESET}\n"

# --- Dependencias mínimas ---
echo -e "${C_CYAN}[*] Verificando dependencias (openssl, xxd, pamtester)...${C_RESET}"
dpkg -s openssl >/dev/null 2>&1 || apt-get install -y openssl >/dev/null 2>&1
command -v xxd >/dev/null 2>&1 || apt-get install -y xxd >/dev/null 2>&1
echo -e "${C_GREEN}[✔] Dependencias listas.${C_RESET}\n"

# --- Pedir contraseña HMAC ---
echo -e "${C_YELLOW}[!] Vamos a configurar la autenticación.${C_RESET}"
echo -e "${C_YELLOW}[!]   root            → contraseña normal${C_RESET}"
echo -e "${C_YELLOW}[!]   otros usuarios  → HMAC obligatorio${C_RESET}"
echo ""
echo -e -n "${C_GREEN}🔑 Contraseña HMAC del servidor: ${C_RESET}"
read -rs PASSWORD
echo ""
if [ -z "$PASSWORD" ]; then
    echo -e "${C_RED}[!] La contraseña no puede estar vacía. Abortando.${C_RESET}"
    exit 1
fi

# --- Backup de /etc/pam.d/sshd ---
PAM_BAK="/etc/pam.d/sshd.bak.$(date +%Y%m%d-%H%M%S)"
cp -a /etc/pam.d/sshd "$PAM_BAK"
echo -e "${C_GREEN}[✔] Backup PAM: $PAM_BAK${C_RESET}"

# --- Escribir verify_local.sh (versión corregida) ---
echo -e "${C_CYAN}[*] Generando /usr/local/bin/verify_local.sh...${C_RESET}"

cat > /usr/local/bin/verify_local.sh <<EOF
#!/bin/bash
set -uo pipefail

PASSWORD='$PASSWORD'
LOG="/var/log/verify_local.log"

log() { echo "[\$(date '+%F %T')] \$*" >> "\$LOG" 2>/dev/null; }

[ -z "\$PASSWORD" ] && { log "ERROR: PASSWORD vacío"; exit 1; }

# pam_exec entrega el token por stdin (expose_authtok)
IFS= read -r input || { log "sin input"; exit 1; }

# Formato esperado: 7 campos separados por ':'
nfields=\$(awk -F':' '{print NF}' <<<"\$input")
if [ "\$nfields" -lt 7 ]; then
    log "PAM_USER=\$PAM_USER formato inválido (nfields=\$nfields)"
    exit 1
fi

timestamp=\$(awk -F':' '{print \$(NF-3)}' <<<"\$input")
signature=\$(awk -F':' '{print \$NF}'     <<<"\$input")
plain=\$(awk -F':' '{for(i=1;i<=NF-6;i++) printf "%s%s", \$i, (i<NF-6?":":"")}' <<<"\$input")

# Ventana estricta: ni pasado >10s, ni futuro >5s
now=\$(date +%s)
if ! [[ "\$timestamp" =~ ^[0-9]+\$ ]]; then
    log "PAM_USER=\$PAM_USER timestamp no numérico"
    exit 1
fi
delta=\$(( now - timestamp ))
if [ "\$delta" -gt 10 ] || [ "\$delta" -lt -5 ]; then
    log "PAM_USER=\$PAM_USER fuera de ventana (delta=\$delta)"
    exit 1
fi

# HMAC
expected=\$(printf '%s:::%s' "\$plain" "\$timestamp" \\
    | openssl dgst -sha256 -hmac "\$PASSWORD" -binary \\
    | xxd -p -c 256)

# Comparación constant-time (sha256 de ambos)
h1=\$(printf '%s' "\$expected"  | sha256sum | awk '{print \$1}')
h2=\$(printf '%s' "\$signature" | sha256sum | awk '{print \$1}')

if [ "\$h1" = "\$h2" ]; then
    log "PAM_USER=\$PAM_USER HMAC OK"
    exit 0
fi

log "PAM_USER=\$PAM_USER HMAC FAIL"
exit 1
EOF

chmod 700 /usr/local/bin/verify_local.sh
chown root:root /usr/local/bin/verify_local.sh

# Crear log con permisos correctos
touch /var/log/verify_local.log
chmod 600 /var/log/verify_local.log
chown root:root /var/log/verify_local.log

echo -e "${C_GREEN}✅ verify_local.sh instalado.${C_RESET}\n"

# --- Configurar /etc/pam.d/sshd ---
echo -e "${C_CYAN}[*] Configurando /etc/pam.d/sshd...${C_RESET}"

# Quitar líneas previas de pam_exec si el script se ha ejecutado antes
sed -i '/pam_exec.so.*verify_local.sh/d' /etc/pam.d/sshd

# Insertar el stack correcto al inicio:
#   1) Si el user es root → saltar pam_exec (success=1)
#   2) Si NO es root  → pam_exec obligatorio (success=done / default=die)
sed -i '1i # ==== HMAC authentication (DevzZJT) ====\nauth [success=1 default=ignore] pam_succeed_if.so user = root\nauth [success=done default=die] pam_exec.so expose_authtok /usr/local/bin/verify_local.sh\n# ==== fin HMAC ====' /etc/pam.d/sshd

echo -e "${C_GREEN}✅ PAM configurado.${C_RESET}"

# --- Validar antes de reiniciar ---
echo -e "${C_CYAN}[*] Validando stack PAM...${C_RESET}"
apt-get install -y pamtester >/dev/null 2>&1 || true

# Mostrar las 5 primeras líneas del stack para confirmar
echo -e "${C_YELLOW}--- /etc/pam.d/sshd (primeras líneas) ---${C_RESET}"
head -n 8 /etc/pam.d/sshd
echo -e "${C_YELLOW}--- fin ---${C_RESET}\n"

# --- Reiniciar SSH ---
echo -e "${C_CYAN}[*] Reiniciando ssh...${C_RESET}"
systemctl restart ssh || systemctl restart sshd
echo -e "${C_GREEN}✅ SSH reiniciado.${C_RESET}\n"

# --- Advertencia final ---
echo -e "${C_YELLOW}════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_YELLOW}  IMPORTANTE — lee antes de cerrar esta sesión:${C_RESET}"
echo -e "${C_YELLOW}════════════════════════════════════════════════════${C_RESET}"
echo -e "  • root        → login con SU CONTRASEÑA de siempre."
echo -e "  • otros users → login con el HMAC (7 campos con ':')."
echo -e "  • NO cierres esta sesión hasta probar en OTRA terminal."
echo -e "  • Si algo falla, restaura con:"
echo -e "      ${C_CYAN}cp $PAM_BAK /etc/pam.d/sshd && systemctl restart ssh${C_RESET}"
echo -e "${C_YELLOW}════════════════════════════════════════════════════${C_RESET}\n"

read -rp "$(echo -e "${C_GREEN}¿Todo bien? Pulsa ENTER para continuar o CTRL+C para abortar...${C_RESET}")" _

# ==========================================
# SSHPLUS
# ==========================================
echo -e "${C_CYAN}====================================================${C_RESET}"
echo -e "${C_GREEN}✅ Configuración HMAC completada.${C_RESET}"
echo -e "${C_CYAN}====================================================${C_RESET}\n"

echo -e "${C_YELLOW}[!] Es RECOMENDABLE instalar SSHPLUS para más funcionalidad.${C_RESET}"
read -rp "$(echo -e "${C_MAGENTA}¿Instalar SSHPLUS ahora? (Y/y/Si/si/N/n/No/no): ${C_RESET}")" RESPONSE

case "$RESPONSE" in
    Y|y|Si|si|SI|Sí|sí)
        echo -e "${C_GREEN}[✔] Instalando SSHPLUS...${C_RESET}\n"
        ;;
    N|n|No|no|NO)
        echo -e "${C_YELLOW}[!] Instalación de SSHPLUS cancelada.${C_RESET}"
        echo -e "${C_GREEN}[✔] Setup de DevzZJT completado.${C_RESET}"
        exit 0
        ;;
    *)
        echo -e "${C_RED}[!] Respuesta no válida.${C_RESET}"
        echo -e "${C_GREEN}[✔] Setup de DevzZJT completado.${C_RESET}"
        exit 0
        ;;
esac

echo -e "${C_CYAN}====================================================${C_RESET}"
echo -e "${C_YELLOW}🚀 Instalando dependencias y SSHPLUS...${C_RESET}"
echo -e "${C_CYAN}====================================================${C_RESET}"
sleep 2
echo -e "${C_CYAN}[*] apt update & upgrade...${C_RESET}"
apt update -y && apt upgrade -y

echo -e "\n${C_CYAN}[*] Descargando Plus...${C_RESET}"
wget -q https://raw.githubusercontent.com/kiritosshxd/SSHPLUS/master/Plus -O /tmp/Plus

echo -e "\n${C_CYAN}[*] Ejecutando Plus...${C_RESET}"
chmod +x /tmp/Plus
bash /tmp/Plus
