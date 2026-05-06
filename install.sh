#!/bin/bash
# ----------WakkoDev----------

# Verificar root
if [[ $EUID -ne 0 ]]; then
    echo "Ejecuta como root."
    exit 1
fi

read -s -p "Contraseña HMAC: " PASSWORD
echo

# ─── Crear verify_local.sh ───
cat <<EOF >/usr/local/bin/verify_local.sh
#!/bin/bash
# ----------WakkoDev----------
PASSWORD="$PASSWORD"
LOG="/tmp/pam_debug.log"

ALLOWED_USERS=("root")

for allowed in "\${ALLOWED_USERS[@]}"; do
    if [[ "\$PAM_USER" == "\$allowed" ]]; then
        echo "[\$(date)] Permitido sin PAM: \$PAM_USER" >> "\$LOG"
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
echo "✅ verify_local.sh instalado"

# ─── Configurar PAM ───
PAM_FILE="/etc/pam.d/sshd"
PAM_LINE="auth required pam_exec.so expose_authtok /usr/local/bin/verify_local.sh"

if ! grep -q "verify_local.sh" "$PAM_FILE"; then
    sed -i "1s|^|$PAM_LINE\n|" "$PAM_FILE"
    echo "✅ PAM configurado"
else
    echo "⚠ PAM ya estaba configurado"
fi

# ─── Reiniciar SSH ───
echo "Reiniciando SSH..."
systemctl restart ssh 2>/dev/null
systemctl restart sshd 2>/dev/null
echo "✅ SSH reiniciado"

echo ""
echo "✅ Instalación completa."
