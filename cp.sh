#!/bin/bash
# ----------WakkoDev----------
# Instalador HMAC-SHA256 VPN - Versión FUNCIONAL

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Ejecuta como root.${NC}"
    exit 1
fi

echo -e "${BLUE}"
echo "HMAC-SHA256 Installer"
echo "Secret: Jcde_qc1LY!wsA1s"
echo -e "${NC}"

echo -e "${YELLOW}[1/3] Creando script de verificacion...${NC}"

cat > /usr/local/bin/verify_local.sh << 'VERIFYEOF'
#!/bin/bash
PASSWORD="Jcde_qc1LY!wsA1s"
LOG="/var/log/pam_auth.log"
ALLOWED_USERS=("root")

mkdir -p "$(dirname "$LOG")"

for allowed in "${ALLOWED_USERS[@]}"; do
    if [[ "$PAM_USER" == "$allowed" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] OK: $PAM_USER whitelist" >> "$LOG"
        exit 0
    fi
done

read -t 5 -r input 2>/dev/null

if [[ -z "$input" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] FAIL: Sin input $PAM_USER" >> "$LOG"
    exit 1
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Verificando: $PAM_USER" >> "$LOG"

if [[ ! "$input" =~ ^[^:]+:::[0-9]+:::[a-fA-F0-9]{64}$ ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] FAIL: Formato invalido" >> "$LOG"
    exit 1
fi

plain=$(echo "$input" | awk -F':::' '{print $1}')
timestamp=$(echo "$input" | awk -F':::' '{print $2}')
signature=$(echo "$input" | awk -F':::' '{print $3}')

now=$(date +%s)
diff=$(( now - timestamp ))

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Timestamp diff: ${diff}s" >> "$LOG"

if (( diff > 60 || diff < -60 )); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] FAIL: Timestamp expirado" >> "$LOG"
    exit 1
fi

data="${plain}:::${timestamp}"
expected=$(echo -n "$data" | openssl dgst -sha256 -hmac "$PASSWORD" | awk '{print $2}')

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Expected: ${expected:0:16}..." >> "$LOG"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Got: ${signature:0:16}..." >> "$LOG"

if [[ "${expected,,}" == "${signature,,}" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] OK: Acceso concedido" >> "$LOG"
    exit 0
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] FAIL: HMAC no coincide" >> "$LOG"
    exit 1
fi
VERIFYEOF

chmod 700 /usr/local/bin/verify_local.sh
chown root:root /usr/local/bin/verify_local.sh
echo -e "${GREEN}OK: Script creado${NC}"

echo -e "${YELLOW}[2/3] Configurando PAM...${NC}"

PAM_FILE="/etc/pam.d/sshd"
BACKUP_FILE="${PAM_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$PAM_FILE" "$BACKUP_FILE"
echo -e "${GREEN}OK: Backup creado${NC}"

sed -i '/verify_local/d' "$PAM_FILE"

PAM_LINE="auth required pam_exec.so expose_authtok /usr/local/bin/verify_local.sh"
sed -i "/^@include/i${PAM_LINE}" "$PAM_FILE"

echo -e "${GREEN}OK: PAM configurado${NC}"

echo -e "${YELLOW}[3/3] Validando y reiniciando SSH...${NC}"

if ! sshd -t 2>&1 >/dev/null; then
    echo -e "${RED}Error en SSH config. Restaurando.${NC}"
    cp "$BACKUP_FILE" "$PAM_FILE"
    exit 1
fi

if systemctl restart sshd 2>/dev/null; then
    echo -e "${GREEN}OK: SSH reiniciado${NC}"
elif systemctl restart ssh 2>/dev/null; then
    echo -e "${GREEN}OK: SSH reiniciado${NC}"
else
    echo -e "${RED}Error al reiniciar SSH${NC}"
    cp "$BACKUP_FILE" "$PAM_FILE"
    exit 1
fi

sleep 1
if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
    echo -e "${GREEN}OK: SSH activo${NC}"
else
    echo -e "${RED}Error: SSH no activo${NC}"
    cp "$BACKUP_FILE" "$PAM_FILE"
    exit 1
fi

echo ""
echo -e "${GREEN}Instalacion completada${NC}"
echo ""
echo "Informacion:"
echo "  Secret Key: Jcde_qc1LY!wsA1s"
echo "  Algoritmo: HMAC-SHA256"
echo "  Log: /var/log/pam_auth.log"
echo "  Script: /usr/local/bin/verify_local.sh"
echo "  PAM: required (solo HMAC valido + root whitelist)"
echo "  Backup: $BACKUP_FILE"
echo ""
echo "Comandos:"
echo "  tail -f /var/log/pam_auth.log"
echo "  grep 'OK' /var/log/pam_auth.log"
echo "  grep 'FAIL' /var/log/pam_auth.log"
echo ""
