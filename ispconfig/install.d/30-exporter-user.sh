#!/usr/bin/env bash
set -euo pipefail

MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-$(openssl rand -base64 16)}"
if ! mysql -uroot -e "SELECT 1;" >/dev/null 2>&1; then
  echo "Definindo senha do root MariaDB..."
  mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}'; FLUSH PRIVILEGES;"
fi

EXPORTER_PWD=$(openssl rand -base64 16)
mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "
  CREATE USER IF NOT EXISTS 'exporter'@'localhost' IDENTIFIED BY '${EXPORTER_PWD}';
  GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';
  FLUSH PRIVILEGES;"

echo -e "[client]\nuser=exporter\npassword=${EXPORTER_PWD}" > /etc/.mysqld_exporter.cnf
chown root:root /etc/.mysqld_exporter.cnf
chmod 600 /etc/.mysqld_exporter.cnf
echo "Usuário exporter criado."
