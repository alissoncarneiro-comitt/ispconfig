#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "This installer must be run as root." >&2
    exit 1
fi

apt update
apt install -y \
  zstd lz4 jq net-tools sysstat \
  htop iotop iftop ncdu \
  auditd libpam-google-authenticator \
  curl sudo wget gnupg build-essential ca-certificates \
  git lsb-release \
  wireguard-tools

echo "\n Iniciando execução do setup.sh..."
bash -x ./nginx/setup.sh | tee nginx-build.log
echo "\nFinalizado setup.sh"


echo "\n Instalando PHP-FPM..."
bash ./php/setup-fpm.sh
echo "\n Finalizado PHP-FPM"

echo "\n Otimizando Maria DB..."
cp -n ./db/50-server-optimized-32gb.cnf /opt/50-server-optimized-32gb.cnf


echo "\n\n Executando instalador do ISPConfig..."
bash ./ispconfig/main-install.sh


echo "\n\n Aplicando template NGINX com socket..."
cp ./nginx/templates/nginx_vhost.conf.master /usr/local/ispconfig/server/conf/


echo "\n\n Instalando Prometheus, Grafana e exporters..."
bash ./monitoring/setup.sh

echo "\n\n ####### Provisionamento completo! ####### \n\n"