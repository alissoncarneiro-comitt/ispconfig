#!/usr/bin/env bash
set -euo pipefail

apt update
apt install -y \
  zstd lz4 jq net-tools sysstat \
  htop iotop iftop ncdu \
  auditd libpam-google-authenticator \
  wireguard-tools ceph-fuse

echo "Instalando NGINX..."
bash ./nginx/setup.sh


echo "Instalando PHP-FPM..."
bash ./php/setup-fpm.sh


cp -n ./db/50-server-optimized-32gb.cnf /opt/50-server-optimized-32gb.cnf


echo "Executando instalador do ISPConfig..."
bash ./ispconfig/main-install.sh              


echo "Aplicando template NGINX com socket..."
cp ./nginx/templates/nginx_vhost.conf.master /usr/local/ispconfig/server/conf/


echo "Instalando Prometheus, Grafana e exporters..."
bash ./monitoring/setup.sh

echo "Provisionamento completo!"
