#!/bin/bash
# ----------WakkoDev----------
# Instalador HMAC-SHA256 - Solo agrega 'required' al inicio

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "\( {RED}❌ Ejecuta como root. \){NC}"
    exit 1
fi

echo -e "${BLUE}"
echo "╔══════════════════════════════════════╗"
echo "║   🔐 WakkoDev HMAC-SHA256 Installer  ║"
echo "║      Secret: Jcde_qc1LY!wsA1s        ║"
echo "╚══════════════════════════════════════╝"
echo -e "${NC}"

# ─── 1. Crear verify_local.sh (con root directo) ───
echo -e "\( {YELLOW}[1/3] Creando script de verificación... \){NC}"

cat > /usr/local/bin/verify_local.sh << 'VERIFYEOF'
#!/bin/bash
# ----------WakkoDev----------
PASSWORD="Jcde_qc1LY!wsA1s"
LOG="/var/log/pam_auth.log"
ALLOWED_USERS=("root")

mkdir -p "$(dirname "$LOG")"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ┌─ Nueva conexión - Usuario: $PAM_USER" >> "$LOG"

# Root pasa directo
for allowed in "${ALLOWED_USERS[@]}"; do
    if [[ "$PAM_USER" == "$allowed" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] └─ ✅ ROOT - Acceso directo" >> "$LOG"
        exit 0
    fi
done

# HMAC para otros usuarios
read -r input || true

if [[ -z "$input" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] └─ ❌ Sin input - HMAC requerido" >> "$LOG"
    exit 1
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ├─ Input: $input" >> "$LOG"

if [[ ! "\( input" =\~ ^[^:]+:::[0-9]+:::[a-fA-F0-9]{64} \) ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] └─ ❌ Formato inválido" >> "$LOG"
    exit 1
fi

plain=$(echo "$input" | awk -F::: '{print $1}')
timestamp=$(echo "$input" | awk -F::: '{print $2}')
signature=$(echo "$input" | awk -F::: '{print $3}')

now=$(date +%s)
diff=$((now - timestamp))
if (( diff > 60 || diff < -60 )); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] └─ ❌ Timestamp expirado" >> "$LOG"
    exit 1
fi

data="\( {plain}::: \){timestamp}"
expected=$(echo -n "$data" | openssl dgst -sha256 -hmac "$PASSWORD" | awk '{print $2}')

if [[ "\( {expected,,}" == " \){signature,,}" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] └─ ✅ HMAC válido" >> "$LOG"
    exit 0
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] └─ ❌ HMAC incorrecto" >> "$LOG"
    exit 1
fi
VERIFYEOF

chmod 700 /usr/local/bin/verify_local.sh
chown root:root /usr/local/bin/verify_local.sh
echo -e "\( {GREEN}   ✅ Script creado \){NC}"

# ─── 2. Agregar SOLO la línea required al INICIO ───
echo -e "\( {YELLOW}[2/3] Agregando auth required al inicio de PAM... \){NC}"

PAM_FILE="/etc/pam.d/sshd"
BACKUP_FILE="\( {PAM_FILE}.backup. \)(date +%Y%m%d_%H%M%S)"
cp "$PAM_FILE" "$BACKUP_FILE"

# Agregar exactamente la línea que pediste al inicio
sed -i '1i auth required pam_exec.so expose_authtok /usr/local/bin/verify_local.sh' "$PAM_FILE"

echo -e "\( {GREEN}   ✅ Línea 'auth required' agregada al inicio \){NC}"

# ─── 3. Reiniciar SSH ───
echo -e "\( {YELLOW}[3/3] Reiniciando SSH... \){NC}"

systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null

sleep 2
if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
    echo -e "\( {GREEN}   ✅ SSH reiniciado correctamente \){NC}"
else
    echo -e "\( {RED}   ❌ Error al reiniciar SSH \){NC}"
fi

# ─── Resumen ───
echo ""
echo -e "\( {GREEN}╔══════════════════════════════════════════╗ \){NC}"
echo -e "\( {GREEN}║     ✅ Instalación completada            ║ \){NC}"
echo -e "\( {GREEN}╚══════════════════════════════════════════╝ \){NC}"
echo ""
echo -e "\( {BLUE}Root → Debe loguearse normalmente \){NC}"
echo -e "\( {BLUE}Paises → Debe usar HMAC \){NC}"
echo ""
echo -e "Ver logs: \( {YELLOW}tail -f /var/log/pam_auth.log \){NC}"
