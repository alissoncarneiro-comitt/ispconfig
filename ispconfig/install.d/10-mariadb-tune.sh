#!/usr/bin/env bash
set -euo pipefail
echo "🔧 Aplicando tuning MariaDB..."

TUNE=/opt/50-server-optimized-32gb.cnf
if [[ ! -f "$TUNE" ]]; then
  echo "❌ Tuning file $TUNE ausente!" >&2
  exit 1
fi

cp "$TUNE" /etc/mysql/mariadb.conf.d/50-server.cnf
chown root:root /etc/mysql/mariadb.conf.d/50-server.cnf
chmod 644  /etc/mysql/mariadb.conf.d/50-server.cnf

mkdir -p /var/log/mysql
touch /var/log/mysql/slow.log
chown mysql:mysql /var/log/mysql/slow.log

systemctl restart mariadb
echo "✅ MariaDB tunado & reiniciado."
