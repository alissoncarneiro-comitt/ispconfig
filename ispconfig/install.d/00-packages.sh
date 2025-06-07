#!/usr/bin/env bash
set -euo pipefail

echo "📦 Instalando pacotes base..."
apt update
apt install -y sudo bash git curl unzip cron mariadb-server mariadb-client \
  pure-ftpd postfix certbot dnsutils rclone gnupg
