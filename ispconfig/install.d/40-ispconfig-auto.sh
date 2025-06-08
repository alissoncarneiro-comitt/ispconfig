#!/usr/bin/env bash
set -euo pipefail
source /opt/ispconfig-env.sh

if [[ -f "$INSTALL_FLAG" ]]; then
  echo "ISPConfig já instalado, pulando etapa."
  exit 0
fi

echo "Clonando autoinstaller ISPConfig..."
cd /tmp
rm -rf ispconfig-autoinstaller
git clone https://git.ispconfig.org/ispconfig/ispconfig-autoinstaller.git
cd ispconfig-autoinstaller

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
use_webmail=y
use_ftp=y
use_jailkit=n
use_fail2ban=y
use_firewall=y
use_dashboard=y
use_monit=y
use_lets_encrypt=y
auto_configure_ssl=y
EOF

echo "Rodando autoinstaller..."
bash install.sh --autoinstall=autoinstall.ini

echo "Limpando pools default..."
for ver in 8.2 8.3 8.4; do
  rm -f /etc/php/${ver}/fpm/pool.d/www.conf || true
  systemctl restart php${ver}-fpm || true
done

touch "$INSTALL_FLAG"
