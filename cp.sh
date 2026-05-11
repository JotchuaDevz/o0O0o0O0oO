#!/bin/bash
# ----------WakkoDev----------
# Instalador HMAC-SHA256 VPN - Versión Final Corregida
# Secret Key: Jcde_qc1LY!wsA1s

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ Ejecuta como root.${NC}"
    exit 1
fi

echo -e "${BLUE}"
echo "╔══════════════════════════════════════╗"
echo "║   🔐 WakkoDev HMAC-SHA256 Installer  ║"
echo "║      Secret: Jcde_qc1LY!wsA1s        ║"
echo "╚══════════════════════════════════════╝"
echo -e "${NC}"

# ─── 1. Crear verify_local.sh ───
echo -e "${YELLOW}[1/4] Creando script de verificación...${NC}"

cat > /usr/local/bin/verify_local.sh << 'VERIFYEOF'
#!/bin/bash
# ----------WakkoDev----------
# Verificación HMAC-SHA256 para VPN
# Secret Key: Jcde_qc1LY!wsA1s

PASSWORD="Jcde_qc1LY!wsA1s"
LOG="/var/log/pam_auth.log"
ALLOWED_USERS=("root")

# Crear directorio de logs si no existe
mkdir -p "$(dirname "$LOG")"

# Root y usuarios en lista blanca pasan sin verificación
for allowed in "${ALLOWED_USERS[@]}"; do
    if [[ "$PAM_USER" == "$allowed" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $PAM_USER - Acceso directo (whitelist)" >> "$LOG"
        exit 0
    fi
done

# Leer input del cliente
read -r input

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ┌─ Nueva conexión" >> "$LOG"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ├─ Usuario: $PAM_USER" >> "$LOG"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ├─ Input: $input" >> "$LOG"

# Validar formato: user:::timestamp:::hmac_sha256_hex (64 chars hex)
if [[ ! "$input" =~ ^[^:]+:::[0-9]+:::[a-fA-F0-9]{64}$ ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] └─ ❌ FAIL - Formato inválido" >> "$LOG"
    exit 1
fi

# Extraer componentes
plain=$(echo "$input" | awk -F':::' '{print $1}')
timestamp=$(echo "$input" | awk -F':::' '{print $2}')
signature=$(echo "$input" | awk -F':::' '{print $3}')

now=$(date +%s)
diff=$(( now - timestamp ))

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ├─ Timestamp diff: ${diff}s" >> "$LOG"

# Verificar timestamp (60 segundos de margen)
if (( diff > 60 || diff < -60 )); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] └─ ❌ FAIL - Timestamp expirado" >> "$LOG"
    exit 1
fi

# Calcular HMAC-SHA256 esperado
data="${plain}:::${timestamp}"
expected=$(echo -n "$data" | openssl dgst -sha256 -hmac "$PASSWORD" | awk '{print $2}')

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ├─ Expected: ${expected:0:16}..." >> "$LOG"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ├─ Got:      ${signature:0:16}..." >> "$LOG"

# Comparar case-insensitive
if [[ "${expected,,}" == "${signature,,}" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] └─ ✅ OK - Acceso concedido" >> "$LOG"
    exit 0
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] └─ ❌ FAIL - HMAC no coincide" >> "$LOG"
    exit 1
fi
VERIFYEOF

# Permisos
chmod 700 /usr/local/bin/verify_local.sh
chown root:root /usr/local/bin/verify_local.sh
echo -e "${GREEN}   ✅ Script creado en /usr/local/bin/verify_local.sh${NC}"

# ─── 2. Configurar PAM ───
echo -e "${YELLOW}[2/4] Configurando PAM...${NC}"

PAM_FILE="/etc/pam.d/sshd"

# Backup con timestamp
BACKUP_FILE="${PAM_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$PAM_FILE" "$BACKUP_FILE"
echo -e "${GREEN}   ✅ Backup creado: $BACKUP_FILE${NC}"

# Eliminar líneas viejas de verify_local
sed -i '/verify_local/d' "$PAM_FILE"

# Insertar como SUFFICIENT (si pasa, no pide más auth)
PAM_LINE="auth sufficient pam_exec.so expose_authtok /usr/local/bin/verify_local.sh"
sed -i "1i${PAM_LINE}" "$PAM_FILE"

echo -e "${GREEN}   ✅ PAM configurado como 'sufficient'${NC}"
echo -e "${BLUE}   📝 Nota: sufficient = si HMAC es válido, no pide contraseña del sistema${NC}"

# ─── 3. Verificar/crear usuarios ───
echo -e "${YELLOW}[3/4] Verificando usuarios...${NC}"

# Lista de usuarios que necesitan acceso VPN
USERS=("Paises")

for user in "${USERS[@]}"; do
    if id "$user" &>/dev/null; then
        echo -e "${GREEN}   ✅ Usuario '$user' existe${NC}"
    else
        echo -e "${YELLOW}   ⚠ Usuario '$user' no existe. Creando...${NC}"
        useradd -m -s /bin/bash "$user"
        echo -e "${YELLOW}   🔑 Establece contraseña para '$user':${NC}"
        passwd "$user"
    fi
done

# ─── 4. Reiniciar servicios ───
echo -e "${YELLOW}[4/4] Reiniciando SSH...${NC}"

if systemctl restart sshd 2>/dev/null; then
    echo -e "${GREEN}   ✅ SSH reiniciado correctamente${NC}"
elif systemctl restart ssh 2>/dev/null; then
    echo -e "${GREEN}   ✅ SSH reiniciado correctamente${NC}"
else
    echo -e "${RED}   ❌ Error al reiniciar SSH${NC}"
fi

# Verificar que SSH está corriendo
sleep 1
if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
    echo -e "${GREEN}   ✅ SSH está activo${NC}"
else
    echo -e "${RED}   ❌ SSH no está corriendo${NC}"
fi

# ─── Resumen final ───
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     ✅ Instalación completada            ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📋 Información:${NC}"
echo -e "   • Secret Key:    ${GREEN}Jcde_qc1LY!wsA1s${NC}"
echo -e "   • Algoritmo:     ${GREEN}HMAC-SHA256${NC}"
echo -e "   • Log:           ${GREEN}/var/log/pam_auth.log${NC}"
echo -e "   • Script:        ${GREEN}/usr/local/bin/verify_local.sh${NC}"
echo -e "   • PAM:           ${GREEN}sufficient (no pide pass extra)${NC}"
echo -e "   • Root:          ${GREEN}Siempre permitido${NC}"
echo ""
echo -e "${BLUE}📊 Comandos útiles:${NC}"
echo -e "   • Ver logs:      ${YELLOW}tail -f /var/log/pam_auth.log${NC}"
echo -e "   • Ver OK:        ${YELLOW}grep 'OK' /var/log/pam_auth.log${NC}"
echo -e "   • Ver FAIL:      ${YELLOW}grep 'FAIL' /var/log/pam_auth.log${NC}"
echo -e "   • Test manual:   ${YELLOW}echo 'test:::\$(date +%s):::\$(echo -n \"test:::\$(date +%s)\" | openssl dgst -sha256 -hmac 'Jcde_qc1LY!wsA1s' | awk '{print \$2}')' | PAM_USER=Paises /usr/local/bin/verify_local.sh${NC}"
echo ""
echo -e "${BLUE}🔑 Para la app (código C++):${NC}"
echo -e "   Formato:         ${YELLOW}password:::timestamp:::hmac_sha256_hex${NC}"
echo -e "   HMAC de:         ${YELLOW}\"password:::timestamp\"${NC}"
echo -e "   con clave:       ${YELLOW}Jcde_qc1LY!wsA1s${NC}"
echo ""
