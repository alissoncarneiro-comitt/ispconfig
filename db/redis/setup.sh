#!/usr/bin/env bash
set -euo pipefail

echo "\n📦 Instalando Redis Server..."
apt update
apt install -y redis-server

systemctl enable redis-server
systemctl start redis-server

echo "Redis Server instalado e em execucao."
