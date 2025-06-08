#!/usr/bin/env bash
set -euo pipefail
source env.sh

# Permite forçar reinstalação com FORCE_INSTALL=1
if [[ -f "$INSTALL_FLAG" && "${FORCE_INSTALL:-0}" != "1" ]]; then
  echo "ISPConfig já instalado (flag $INSTALL_FLAG presente). Para forçar, exporte FORCE_INSTALL=1 e execute novamente."
  exit 0
elif [[ "${FORCE_INSTALL:-0}" == "1" ]]; then
  echo "FORCE_INSTALL detectado, removendo flag existente..."
  rm -f "$INSTALL_FLAG"
fi

# Clona o autoinstaller ISPConfig
TMPDIR="/tmp/ispconfig-autoinstaller"
rm -rf "$TMPDIR"
echo "➤ Clonando autoinstaller ISPConfig..."
git clone https://git.ispconfig.org/ispconfig/ispconfig-autoinstaller.git "$TMPDIR"
cd "$TMPDIR"

# Gera autoinstall.ini com flags desejadas
echo "➤ Gerando autoinstall.ini"
cat > autoinstall.ini <<EOF
[install]
language=en
install_mode=standard
hostname=$(hostname -f)
mysql_hostname=localhost
mysql_root_password=${MYSQL_ROOT_PASSWORD}
mysql_database=dbispconfig
mysql_charset=utf8mb4
ispconfig_port=8080
ispconfig_use_ssl=y
ssl_letsencrypt=y
nginx=y
php=y
php_versions=8.2,8.3,8.4
use_pureftpd=y
use_mailman=n
use_webmail=n
use_ftp=y
use_jailkit=y
use_fail2ban=y
use_firewall=y
use_dashboard=y
auto_configure_ssl=y
EOF

# Instala pacotes de sistema necessários antes do autoinstaller
echo "➤ Instalando pacotes para suporte às flags..."
declare -A PKG_MAP=(
  [use_pureftpd]=pure-ftpd
  [use_ftp]=pure-ftpd
  [use_jailkit]=jailkit
  [use_fail2ban]=fail2ban
  [use_firewall]=iptables-persistent
  [use_dashboard]=monit
  [use_lets_encrypt]=certbot
)
for flag in "${!PKG_MAP[@]}"; do
  if grep -q "^${flag}=y" autoinstall.ini; then
    pkg=${PKG_MAP[$flag]}
    echo "  ➤ Instalando $pkg para $flag..."
    apt update && apt install -y --no-install-recommends "$pkg"
  fi
done

# Detecta script de instalação correto
echo "➤ Localizando instalador..."
if [[ -x "$TMPDIR/ispc3-ai.sh" ]]; then
  INSTALL_SCRIPT="$TMPDIR/ispc3-ai.sh"
elif [[ -x "$TMPDIR/install.sh" ]]; then
  INSTALL_SCRIPT="$TMPDIR/install.sh"
else
  echo "❌ Nenhum instalador encontrado em $TMPDIR"
  ls -1 "$TMPDIR"
  exit 1
fi

# Executa o autoinstaller com flags de linha de comando
echo "➤ Executando instalador $(basename "$INSTALL_SCRIPT")..."
bash "$INSTALL_SCRIPT" \
  --channel=stable \
  --lang=en \
  --use-nginx \
  --no-mail \
  --no-roundcube \
  --no-mailman \
  --use-ftp-ports=40110-40210 \
  --i-know-what-i-am-doing \
  --autoinstall=autoinstall.ini
  
# Limpa pools default e reinicia PHP-FPM
echo "➤ Limpando pools default e reiniciando PHP-FPM"
for ver in 8.2 8.3 8.4; do
  rm -f /etc/php/${ver}/fpm/pool.d/www.conf || true
  if command -v service >/dev/null 2>&1; then
    service php${ver}-fpm restart || true
  elif command -v systemctl >/dev/null 2>&1 && pidof systemd >/dev/null 2>&1; then
    systemctl restart php${ver}-fpm || true
  else
    echo "ℹ️ Reinicie php${ver}-fpm manualmente."
  fi
done
# Marca como instalado
touch "$INSTALL_FLAG"
echo "✅ ISPConfig instalado com sucesso!"
