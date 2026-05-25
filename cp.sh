#!/bin/bash
# ----------WakkoDev----------
# Instalador HMAC-SHA256 VPN - Versión Corregida (Root normal + HMAC obligatorio)
# Secret Key: Jcde_qc1LY!wsA1s

# Colores
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

# ─── 1. Crear verify_local.sh (Versión Corregida) ───
echo -e "\( {YELLOW}[1/4] Creando script de verificación... \){NC}"

cat > /usr/local/bin/verify_local.sh << 'VERIFYEOF'
#!/bin/bash
# ----------WakkoDev - Versión Corregida----------
# Root: login normal | Otros usuarios: HMAC obligatorio

PASSWORD="Jcde_qc1LY!wsA1s"
LOG="/var/log/pam_auth.log"
ALLOWED_USERS=("root")

mkdir -p "$(dirname "$LOG")"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ┌─ Nueva conexión - Usuario: $PAM_USER" >> "$LOG"

# ROOT: Permitir siempre (login normal)
for allowed in "${ALLOWED_USERS[@]}"; do
    if [[ "$PAM_USER" == "$allowed" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] └─ ✅ ROOT - Acceso directo sin HMAC" >> "$LOG"
        exit 0
    fi
done

# === USUARIOS NORMALES: Requieren HMAC ===
read -r input || true

if [[ -z "$input" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] └─ ❌ No input - HMAC requerido para este usuario" >> "$LOG"
    exit 1
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ├─ Input: $input" >> "$LOG"

# Validar formato: user:::timestamp:::hmac (64 chars hex)
if [[ ! "\( input" =\~ ^[^:]+:::[0-9]+:::[a-fA-F0-9]{64} \) ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] └─ ❌ Formato inválido" >> "$LOG"
    exit 1
fi

plain=$(echo "$input" | awk -F::: '{print $1}')
timestamp=$(echo "$input" | awk -F::: '{print $2}')
signature=$(echo "$input" | awk -F::: '{print $3}')

# Verificar timestamp (±60 segundos)
now=$(date +%s)
diff=$(( now - timestamp ))
if (( diff > 60 || diff < -60 )); then
    echo "[\( (date '+%Y-%m-%d %H:%M:%S')] └─ ❌ Timestamp expirado ( \){diff}s)" >> "$LOG"
    exit 1
fi

# Calcular HMAC-SHA256
data="\( {plain}::: \){timestamp}"
expected=$(echo -n "$data" | openssl dgst -sha256 -hmac "$PASSWORD" | awk '{print $2}')

if [[ "\( {expected,,}" == " \){signature,,}" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] └─ ✅ HMAC válido - Acceso concedido" >> "$LOG"
    exit 0
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] └─ ❌ HMAC incorrecto" >> "$LOG"
    exit 1
fi
VERIFYEOF

chmod 700 /usr/local/bin/verify_local.sh
chown root:root /usr/local/bin/verify_local.sh
echo -e "\( {GREEN}   ✅ Script creado en /usr/local/bin/verify_local.sh \){NC}"

# ─── 2. Configurar PAM ───
echo -e "\( {YELLOW}[2/4] Configurando PAM... \){NC}"

PAM_FILE="/etc/pam.d/sshd"
BACKUP_FILE="\( {PAM_FILE}.backup. \)(date +%Y%m%d_%H%M%S)"
cp "$PAM_FILE" "$BACKUP_FILE"
echo -e "${GREEN}   ✅ Backup creado: \( BACKUP_FILE \){NC}"

# Reemplazar configuración PAM
cat > "$PAM_FILE" << 'PAMEOF'
# PAM configuration for the Secure Shell service

# HMAC Verification (Root pasa directo, otros requieren HMAC)
auth [success=1 default=ignore] pam_exec.so expose_authtok /usr/local/bin/verify_local.sh

# Si HMAC falla para usuarios normales → denegar
auth requisite pam_deny.so

# Autenticación normal del sistema (contraseña, keys, etc.)
@include common-auth
@include common-account
@include common-session
PAMEOF

echo -e "\( {GREEN}   ✅ PAM configurado correctamente \){NC}"
echo -e "\( {BLUE}   📝 Root = normal | Otros usuarios = HMAC obligatorio \){NC}"

# ─── 3. Verificar/crear usuarios ───
echo -e "\( {YELLOW}[3/4] Verificando usuarios... \){NC}"

USERS=("Paises")

for user in "${USERS[@]}"; do
    if id "$user" &>/dev/null; then
        echo -e "${GREEN}   ✅ Usuario '\( user' ya existe \){NC}"
    else
        echo -e "${YELLOW}   ⚠ Creando usuario '\( user'... \){NC}"
        useradd -m -s /bin/bash "$user"
        echo -e "${YELLOW}   🔑 Establece una contraseña para '\( user': \){NC}"
        passwd "$user"
    fi
done

# ─── 4. Reiniciar servicios ───
echo -e "\( {YELLOW}[4/4] Reiniciando SSH... \){NC}"

systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null

sleep 2
if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
    echo -e "\( {GREEN}   ✅ SSH reiniciado correctamente \){NC}"
else
    echo -e "\( {RED}   ❌ Error al reiniciar SSH \){NC}"
fi

# ─── Resumen final ───
echo ""
echo -e "\( {GREEN}╔══════════════════════════════════════════╗ \){NC}"
echo -e "\( {GREEN}║     ✅ Instalación completada            ║ \){NC}"
echo -e "\( {GREEN}╚══════════════════════════════════════════╝ \){NC}"
echo ""
echo -e "\( {BLUE}📋 Información: \){NC}"
echo -e "   • Secret Key:    \( {GREEN}Jcde_qc1LY!wsA1s \){NC}"
echo -e "   • Root:           \( {GREEN}Login normal (sin HMAC) \){NC}"
echo -e "   • Otros usuarios: \( {GREEN}HMAC obligatorio \){NC}"
echo -e "   • Log:            \( {GREEN}/var/log/pam_auth.log \){NC}"
echo ""
echo -e "\( {BLUE}📊 Comandos útiles: \){NC}"
echo -e "   tail -f /var/log/pam_auth.log"
echo ""
echo -e "\( {BLUE}🔑 Formato para la app: \){NC}"
echo -e "   password:::timestamp:::hmac_sha256"
echo ""
