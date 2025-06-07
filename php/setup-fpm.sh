#!/bin/bash
set -e
set -o pipefail

export DEBIAN_FRONTEND=noninteractive
INSTALL_IONCUBE=${INSTALL_IONCUBE:-no}

PHP_VERSIONS=(8.2 8.3 8.4)
EXTENSIONS_COMMON=(bcmath gmp intl gd imagick mbstring xml soap zip curl fileinfo json opcache sodium cli common)
EXTENSIONS_DB=(mysql pgsql sqlite3)
EXTENSIONS_CACHE=(redis memcached)
EXTENSIONS_OTHER=(fpm)
PECL_EXTENSIONS=(xdebug swoole yaml rdkafka grpc mongodb apcu blackfire newrelic)
INI_DIR="/etc/php"

calculate_children() {
    local mem=$(free -m | awk '/Mem:/ {print $2}')
    echo $((mem / 100))
}

echo "🧩 Instalando dependências base..."
apt update
apt install -y --no-install-recommends \
    software-properties-common curl lsb-release ca-certificates gnupg apt-transport-https \
    build-essential pkg-config unzip autoconf automake libtool libssl-dev cmake git \
    libpcre3-dev libcurl4-openssl-dev libzip-dev zlib1g-dev libyaml-dev libonig-dev \
    libgmp-dev libicu-dev libjpeg-dev libpng-dev libwebp-dev libfreetype6-dev \
    libkrb5-dev libxml2-dev libmemcached-dev libevent-dev librdkafka-dev libsasl2-dev \
    php-pear php-dev php-igbinary php-msgpack

echo "📦 Adicionando repositório SURY..."
curl -fsSL https://packages.sury.org/php/apt.gpg | tee /etc/apt/trusted.gpg.d/php.gpg > /dev/null
echo "deb https://packages.sury.org/php $(lsb_release -cs) main" > /etc/apt/sources.list.d/php-sury.list
apt update

for version in "${PHP_VERSIONS[@]}"; do
    echo "📦 Instalando PHP $version e extensões..."
    apt install -y --no-install-recommends php${version}-{${EXTENSIONS_COMMON[*]}} php${version}-{${EXTENSIONS_DB[*]}} php${version}-{${EXTENSIONS_CACHE[*]}} php${version}-{${EXTENSIONS_OTHER[*]}}

    update-alternatives --install /usr/bin/php php /usr/bin/php${version} ${version//./}
    update-alternatives --install /usr/bin/phpize phpize /usr/bin/phpize${version} ${version//./}
    update-alternatives --install /usr/bin/php-config php-config /usr/bin/php-config${version} ${version//./}

    PHP_INI_FPM="${INI_DIR}/${version}/fpm/php.ini"
    PHP_INI_CLI="${INI_DIR}/${version}/cli/php.ini"

    for PHP_INI in "$PHP_INI_FPM" "$PHP_INI_CLI"; do
        [ -f "$PHP_INI" ] || continue
        sed -i 's/^memory_limit = .*/memory_limit = 512M/' "$PHP_INI"
        sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 100M/' "$PHP_INI"
        sed -i 's/^post_max_size = .*/post_max_size = 100M/' "$PHP_INI"
        sed -i 's/^max_execution_time = .*/max_execution_time = 60/' "$PHP_INI"
        sed -i 's~^;?date.timezone =.*~date.timezone = America/Sao_Paulo~' "$PHP_INI"
        sed -i 's/^;?expose_php = .*/expose_php = Off/' "$PHP_INI"
        sed -i 's/^;?display_errors = .*/display_errors = Off/' "$PHP_INI"
        sed -i 's/^;?log_errors = .*/log_errors = On/' "$PHP_INI"
        sed -i 's/^;?error_log = .*/error_log = \/var\/log\/php\/php${version}-fpm.log/' "$PHP_INI"

        cat << EOF >> "$PHP_INI"

[opcache]
opcache.enable=1
opcache.memory_consumption=256
opcache.max_accelerated_files=100000
opcache.interned_strings_buffer=16
opcache.jit=1255
opcache.jit_buffer_size=64M
EOF
        done

        echo "🧪 Instalando extensões PECL para PHP $version..."
        for ext in "${PECL_EXTENSIONS[@]}"; do
            echo "➡️ Instalando $ext para PHP $version..."
            if ! yes '' | pecl install -f "${ext}"; then
                echo "❌ Falha ao instalar $ext para PHP $version" >&2
                continue
            fi
            ext_path="$(php-config${version} --extension-dir)/${ext}.so"
            if [ -f "$ext_path" ]; then
                echo "extension=$ext.so" > "${INI_DIR}/${version}/mods-available/${ext}.ini"
                phpenmod -v ${version} $ext || true
            else
                echo "⚠️ Extensão $ext não encontrada, pode ter falhado no PECL."
            fi
        done

        if [ "$INSTALL_IONCUBE" = "yes" ]; then
            echo "🔐 Instalando ionCube Loader..."
            IONCUBE_DIR="/opt/ioncube"
            mkdir -p "$IONCUBE_DIR"
            curl -fsSL https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz -o /tmp/ioncube.tar.gz
            tar -xzf /tmp/ioncube.tar.gz -C /opt
            cp "${IONCUBE_DIR}/ioncube/ioncube_loader_lin_${version}.so" "$(php-config${version} --extension-dir)/"
            echo "zend_extension=ioncube_loader_lin_${version}.so" > "${INI_DIR}/${version}/mods-available/ioncube.ini"
            phpenmod -v ${version} ioncube
        fi

        echo "📂 Gerando pool socket ISPConfig para PHP $version..."
        children=$(calculate_children)
        MAX_CHILDREN=$children
        MAX_SPARE=$(( children / 2 ))

        envsubst < ./php/pools.d/ispconfig.conf.template \
        > /etc/php/${version}/fpm/pool.d/ispconfig-${version}.conf


        mkdir -p /var/log/php
        chown www-data: /var/log/php

        if command -v systemctl >/dev/null; then
          systemctl enable php${version}-fpm
          systemctl restart php${version}-fpm
        fi
    done

    apt purge -y build-essential pkg-config unzip autoconf automake libtool git cmake
    apt autoremove -y --purge && apt clean

    echo "✅ PHP-FPM multi-versão + ISPConfig + PECL completo instalado!"
