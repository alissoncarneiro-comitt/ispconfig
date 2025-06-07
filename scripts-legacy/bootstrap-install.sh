#!/bin/bash
set -e
apt install -y \
  zstd lz4 jq net-tools sysstat \
  htop iotop iftop ncdu \
  auditd libpam-google-authenticator \
  wireguard-tools ceph-fuse

  
echo "▶ Instalando NGINX com tunning..."
bash ./setup-nginx.sh

echo "▶ Instalando PHP-FPM multi-versão..."
bash ./setup-php-fpm.sh

echo "▶ Instalando ISPConfig..."
bash ./install-ispconfig.sh --no-install-php --no-install-nginx

echo "▶ Aplicando template do NGINX com .sock..."
cp ./templates/nginx_vhost.conf.master /usr/local/ispconfig/server/conf/

echo "📊 Instalando Prometheus, Grafana e exporters para monitoramento..."
bash ./setup-monitoring.sh