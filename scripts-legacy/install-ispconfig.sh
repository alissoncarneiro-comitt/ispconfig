    #!/bin/bash
    set -euo pipefail

    source /opt/ispconfig-env.sh

    echo "📦 Instalando dependências básicas..."
    apt update && apt install -y \
      sudo bash git curl unzip cron mariadb-server mariadb-client \
      pure-ftpd postfix certbot dnsutils \
      rclone gnupg

    # ────────────────────────────────────────────────────────────────
    # Tuning do MariaDB
    # ────────────────────────────────────────────────────────────────
    echo "🔧 Aplicando otimizações de desempenho no MariaDB..."
    TUNE=/opt/50-server-optimized-32gb.cnf
    if [ -f "$TUNE" ]; then
      cp "$TUNE" /etc/mysql/mariadb.conf.d/50-server.cnf
      chown root:root /etc/mysql/mariadb.conf.d/50-server.cnf
      chmod 644 /etc/mysql/mariadb.conf.d/50-server.cnf
    else
      echo "❌ Arquivo de tuning $TUNE não encontrado. Abortando." >&2
      exit 1
    fi
    systemctl restart mariadb

    # Garante que o slow-query log tenha destino válido
    mkdir -p /var/log/mysql
    touch /var/log/mysql/slow.log
    chown mysql:mysql /var/log/mysql/slow.log

    # ────────────────────────────────────────────────────────────────
    # Configuração do Rclone
    # ────────────────────────────────────────────────────────────────
    echo "☁️ Verificando configuração do rclone com Google Drive..."
    mkdir -p /root/.config/rclone

    if ! rclone listremotes | grep -q "^${GDRIVE_REMOTE_NAME}:"; then
      echo "⚠️ Rclone remoto '${GDRIVE_REMOTE_NAME}' ainda não configurado."
      echo "➡️ Execute: rclone config"
      exit 1
    else
      echo "✅ Rclone remoto '${GDRIVE_REMOTE_NAME}' já configurado."
    fi

    mkdir -p "$GDRIVE_BACKUP_FOLDER"

    if [ ! -f "$INSTALL_FLAG" ]; then
      echo "📥 Baixando ISPConfig autoinstaller..."
      cd /tmp
      rm -rf ispconfig-autoinstaller
      git clone https://git.ispconfig.org/ispconfig/ispconfig-autoinstaller.git
      cd ispconfig-autoinstaller

      # ── Senha root MariaDB ───────────────────────────────────────
      MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-$(openssl rand -base64 16)}"
      if ! mysql -uroot -e "SELECT 1;" >/dev/null 2>&1; then
        echo "🔑 Definindo senha do usuário root do MariaDB..."
        mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}'; FLUSH PRIVILEGES;"
      fi

      # ── Usuário exporter para Prometheus ─────────────────────────
      EXPORTER_PWD=$(openssl rand -base64 16)
      mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "
      CREATE USER IF NOT EXISTS 'exporter'@'localhost'
        IDENTIFIED BY '${EXPORTER_PWD}';
      GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';
      FLUSH PRIVILEGES;"
      echo -e "[client]\nuser=exporter\npassword=${EXPORTER_PWD}" > /etc/.mysqld_exporter.cnf
      chown root:root /etc/.mysqld_exporter.cnf
      chmod 600 /etc/.mysqld_exporter.cnf
      echo "✅ Usuário 'exporter' criado e credenciais salvas."

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

      echo "🚀 Executando instalação do ISPConfig via autoinstall.ini..."
      sudo bash install.sh --autoinstall=autoinstall.ini

      echo "🧹 Removendo pools PHP default..."
      for ver in 8.2 8.3 8.4; do
        rm -f /etc/php/${ver}/fpm/pool.d/www.conf || true
        systemctl restart php${ver}-fpm || true
      done

      touch "$INSTALL_FLAG"
    else
      echo "✅ ISPConfig já instalado, pulando autoinstaller."
    fi

    # ────────────────────────────────────────────────────────────────
    # Backup Google Drive
    # ────────────────────────────────────────────────────────────────
    echo "💾 Criando script de backup para Google Drive..."
    mkdir -p /opt/ispconfig-backup
    cat > "$BACKUP_SCRIPT" <<'EOS'
#!/bin/bash
set -e
BACKUP_DIR="/var/backup"
DEST="${GDRIVE_REMOTE_NAME}:ispconfig/$(date +%Y-%m-%d)"
echo "🗃️ Enviando backups para $DEST"
rclone copy $BACKUP_DIR $DEST --progress --create-empty-src-dirs
EOS

    chmod 700 "$BACKUP_SCRIPT"
    chown root:root "$BACKUP_SCRIPT"

    echo "🕒 Agendando backup diário via cron..."
    echo "0 3 * * * root $BACKUP_SCRIPT >> /var/log/ispconfig-gdrive-backup.log 2>&1" > /etc/cron.d/ispconfig-gdrive

    echo "🧹 Criando logrotate para backup..."
    cat > /etc/logrotate.d/ispconfig-gdrive <<'EOF'
/var/log/ispconfig-gdrive-backup.log {
    rotate 7
    daily
    missingok
    notifempty
    compress
    delaycompress
}
EOF

    echo "✅ ISPConfig instalado e integrado com Google Drive via rclone."

    # ────────────────────────────────────────────────────────────────
    # Fail2Ban NGINX custom
    # ────────────────────────────────────────────────────────────────
    echo "🛡️ Configurando Fail2Ban para proteger NGINX..."
    cat > /etc/fail2ban/jail.d/nginx-custom.conf <<'EOF'
[nginx-req-limit]
enabled = true
filter = nginx-req-limit
action = iptables-multiport[name=ReqLimit, port="http,https", protocol=tcp]
logpath = /var/log/nginx/*error.log
findtime = 600
bantime = 7200
maxretry = 10
EOF

    cat > /etc/fail2ban/filter.d/nginx-req-limit.conf <<'EOF'
[Definition]
failregex = limiting requests.*client: <HOST>
ignoreregex =
EOF

    systemctl restart fail2ban
    echo "✅ Fail2Ban configurado com regra personalizada para NGINX."
