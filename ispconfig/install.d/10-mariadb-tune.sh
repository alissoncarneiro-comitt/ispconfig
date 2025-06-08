#!/usr/bin/env bash
set -euo pipefail

echo "➤ Aplicando tuning MariaDB..."

# Local do arquivo de tuning
TUNE="../db/50-server-optimized-32gb.cnf"

if [[ ! -f "$TUNE" ]]; then
  echo "⚠️ Tuning file $TUNE ausente!"
  exit 1
fi

# Copia a configuração otimizada
cp "$TUNE" /etc/mysql/mariadb.conf.d/50-server.cnf
chown root:root /etc/mysql/mariadb.conf.d/50-server.cnf
chmod 644  /etc/mysql/mariadb.conf.d/50-server.cnf

echo "✅ Arquivo de tuning aplicado em /etc/mysql/mariadb.conf.d/50-server.cnf"

# Prepara o slow log
mkdir -p /var/log/mysql
: > /var/log/mysql/slow.log
chown mysql:mysql /var/log/mysql/slow.log && chmod 644 /var/log/mysql/slow.log

echo "✅ Slow log configurado em /var/log/mysql/slow.log"

# Reinício do serviço MariaDB
if systemctl >/dev/null 2>&1 && [ "$(pidof systemd)" = "1" ]; then
    echo "➤ Reiniciando MariaDB via systemctl..."
    systemctl restart mariadb
elif command -v service >/dev/null 2>&1; then
    echo "➤ Reiniciando MariaDB via service..."
    service mysql restart || service mariadb restart
else
    echo "ℹ️ Nenhum gerenciador de serviço detectado. Por favor, reinicie MariaDB manualmente."
fi

echo "✅ MariaDB tunado!"
