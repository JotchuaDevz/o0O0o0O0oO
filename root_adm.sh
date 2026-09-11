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
echo -e "${C_MAGENTA}      Root Access Setup          ${C_RESET}"
echo -e "${C_CYAN}====================================================${C_RESET}"
echo ""

if [[ $EUID -ne 0 ]]; then
    echo -e "${C_RED}[!] Este script debe ejecutarse como root.${C_RESET}"
    exit 1
fi

if [[ ! -f /etc/os-release ]]; then
    echo -e "${C_RED}[!] No se pudo detectar el sistema operativo.${C_RESET}"
    exit 1
fi

source /etc/os-release
echo -e "${C_GREEN}[✔] Sistema detectado: $PRETTY_NAME${C_RESET}\n"

echo -e "${C_CYAN}[*] Estableciendo contraseña para root...${C_RESET}"
while true; do
    echo -e -n "${C_GREEN}🔑 Nueva contraseña para root: ${C_RESET}"
    read -r PASS1
    echo ""
    echo -e -n "${C_GREEN}🔑 Confirmar contraseña: ${C_RESET}"
    read -r PASS2
    echo ""
    if [[ -z "$PASS1" ]]; then
        echo -e "${C_RED}[!] La contraseña no puede estar vacía.${C_RESET}"
        continue
    fi
    if [[ "$PASS1" != "$PASS2" ]]; then
        echo -e "${C_RED}[!] Las contraseñas no coinciden. Intenta de nuevo.${C_RESET}"
        continue
    fi
    break
done

if ! echo "root:$PASS1" | chpasswd 2>/tmp/chpasswd.err; then
    echo -e "${C_RED}[!] Error al establecer la contraseña de root:${C_RESET}"
    cat /tmp/chpasswd.err
    exit 1
fi
unset PASS1 PASS2
echo -e "${C_GREEN}✅ Contraseña de root establecida.${C_RESET}\n"

echo -e "${C_CYAN}[*] Configurando SSH...${C_RESET}"

SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_FILE="/etc/ssh/sshd_config.bak.$(date +%Y%m%d-%H%M%S)"
cp "$SSHD_CONFIG" "$BACKUP_FILE"
echo -e "${C_GREEN}✅ Backup guardado en: $BACKUP_FILE${C_RESET}"

if grep -qE '^\s*#?\s*Include\s+/etc/ssh/sshd_config\.d/\*' "$SSHD_CONFIG"; then
    mkdir -p /etc/ssh/sshd_config.d
    cat >/etc/ssh/sshd_config.d/99-root-access.conf <<EOF
PermitRootLogin yes
PasswordAuthentication yes
EOF
    chmod 600 /etc/ssh/sshd_config.d/99-root-access.conf
    echo -e "${C_GREEN}✅ Override creado en /etc/ssh/sshd_config.d/99-root-access.conf${C_RESET}"
else
    sed -i 's/^\s*#\?\s*PermitRootLogin\s.*/PermitRootLogin yes/' "$SSHD_CONFIG"
    sed -i 's/^\s*#\?\s*PasswordAuthentication\s.*/PasswordAuthentication yes/' "$SSHD_CONFIG"

    grep -qE '^\s*PermitRootLogin\s' "$SSHD_CONFIG" || echo "PermitRootLogin yes" >> "$SSHD_CONFIG"
    grep -qE '^\s*PasswordAuthentication\s' "$SSHD_CONFIG" || echo "PasswordAuthentication yes" >> "$SSHD_CONFIG"

    echo -e "${C_GREEN}✅ sshd_config actualizado.${C_RESET}"
fi

echo -e "${C_CYAN}[*] Validando configuración SSH...${C_RESET}"
if ! sshd -t 2>/tmp/sshd_test.err; then
    echo -e "${C_RED}[!] Error de sintaxis:${C_RESET}"
    cat /tmp/sshd_test.err
    cp "$BACKUP_FILE" "$SSHD_CONFIG"
    [[ -f /etc/ssh/sshd_config.d/99-root-access.conf ]] && rm -f /etc/ssh/sshd_config.d/99-root-access.conf
    exit 1
fi
echo -e "${C_GREEN}✅ Validación OK.${C_RESET}\n"

echo -e "${C_CYAN}[*] Estado actual:${C_RESET}"
grep -E '^\s*(PermitRootLogin|PasswordAuthentication)' "$SSHD_CONFIG" 2>/dev/null
[[ -f /etc/ssh/sshd_config.d/99-root-access.conf ]] && grep -E '^\s*(PermitRootLogin|PasswordAuthentication)' /etc/ssh/sshd_config.d/99-root-access.conf
echo ""

systemctl restart ssh 2>/dev/null || systemctl restart sshd
echo -e "${C_GREEN}✅ Servicio SSH reiniciado.${C_RESET}\n"

echo -e "${C_CYAN}====================================================${C_RESET}"
echo -e "${C_GREEN}✅ Root con contraseña habilitado.${C_RESET}"
echo -e "${C_CYAN}====================================================${C_RESET}\n"
