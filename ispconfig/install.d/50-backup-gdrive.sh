    #!/usr/bin/env bash
    set -euo pipefail
    source /opt/ispconfig-env.sh

    echo "Instalando backup cron GDrive..."
    mkdir -p /opt/ispconfig-backup

    cat > "$BACKUP_SCRIPT" <<'EOS'
#!/bin/bash
set -e
BACKUP_DIR="/var/backup"
DEST="${GDRIVE_REMOTE_NAME}:ispconfig/$(date +%Y-%m-%d)"
echo "Enviando backups para $DEST"
rclone copy $BACKUP_DIR $DEST --progress --create-empty-src-dirs
EOS
    chmod 700 "$BACKUP_SCRIPT"
    chown root:root "$BACKUP_SCRIPT"

    echo "0 3 * * * root $BACKUP_SCRIPT >> /var/log/ispconfig-gdrive-backup.log 2>&1" > /etc/cron.d/ispconfig-gdrive

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
    echo "Backup configurado."
