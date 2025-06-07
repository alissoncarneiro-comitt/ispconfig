#!/usr/bin/env bash
set -euo pipefail
source /opt/ispconfig-env.sh

echo "☁️ Checando configuração do rclone..."
mkdir -p /root/.config/rclone
if ! rclone listremotes | grep -q "^${GDRIVE_REMOTE_NAME}:"; then
  echo "⚠️  Remoto ${GDRIVE_REMOTE_NAME} inexistente. Execute: rclone config" >&2
  exit 1
fi
mkdir -p "$GDRIVE_BACKUP_FOLDER"
echo "✅ rclone ok."
