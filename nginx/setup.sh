#!/bin/bash
set -e
set -o pipefail

################################################################################
# NGINX Custom Build for High-Performance Laravel Hosting
# Recursos:
# - Brotli + Gzip Static
# - HTTP/3 (QUIC) + kTLS
# - GeoIP2 (auto-reload)
# - PageSpeed, njs, Headers-More, DAV, Slice, MP4
# - FastCGI Cache (bypass por cookie, sessão, Auth, Cache-Control)
# - Hardening de segurança
# - Config remoto opcional via $NGINX_CONF_URL
#
# Uso:
#   chmod +x install-nginx-laravel.sh
#   sudo ./install-nginx-laravel.sh
#   # ou
#   NGINX_CONF_URL=https://meu-repo/nginx.conf sudo ./install-nginx-laravel.sh
################################################################################

# ───────────────────────── Variáveis básicas ─────────────────────────
NGINX_VERSION="1.28.0"
OPENSSL_QUIC_BRANCH="openssl-3.3.1+quic"
NJS_VERSION="0.8.2"
PAGESPEED_VERSION="1.13.35.2-stable"
PSOL_VERSION="1.13.35.2-x64-linux"
BUILD_DIR="/tmp/nginx-build"

echo "🚀 Iniciando build NGINX ${NGINX_VERSION} …"

# ───────────────────── Dependências de build ─────────────────────
export DEBIAN_FRONTEND=noninteractive
apt update && apt install -y --no-install-recommends \
  build-essential git wget curl unzip libtool automake autoconf cmake \
  zlib1g-dev libpcre3-dev libmaxminddb-dev \
  libnghttp3-dev libngtcp2-dev pkg-config libssl-dev libgd-dev \
  ca-certificates uuid-dev

# ───────────────────── Diretórios de build/runtime ─────────────────────
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

mkdir -p /etc/nginx/{conf.d,sites-available,sites-enabled,geoip2}
mkdir -p /var/log/nginx /var/cache/nginx /var/run

# ─────────────── Usuário não-root para processo nginx ───────────────
groupadd --system www-data 2>/dev/null || true
useradd  --system --no-create-home --shell /usr/sbin/nologin \
        -g www-data www-data 2>/dev/null || true
chown -R www-data:www-data /var/log/nginx /var/cache/nginx

# ─────────────── Função retry (back-off exponencial) ───────────────
retry() {
  local n=0
  until "$@"; do
    n=$((n+1)); [[ $n -lt 5 ]] || exit 1
    echo "🔄 Retry $n…"
    sleep $((2 ** n))
  done
}

# ───────────────────── Baixar fontes principais ─────────────────────
retry wget -q http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz
tar -xzf nginx-${NGINX_VERSION}.tar.gz

git clone --recursive https://github.com/google/ngx_brotli.git
git clone https://github.com/openresty/headers-more-nginx-module.git
git clone https://github.com/leev/ngx_http_geoip2_module.git
git clone https://github.com/apache/incubator-pagespeed-ngx.git pagespeed
pushd pagespeed >/dev/null
git checkout -q v${PAGESPEED_VERSION}
retry wget -q https://dl.google.com/dl/page-speed/psol/${PSOL_VERSION}.tar.gz \
      -O ${PSOL_VERSION}.tar.gz
tar -xzf ${PSOL_VERSION}.tar.gz
popd >/dev/null

git clone --depth=1 -b ${OPENSSL_QUIC_BRANCH} https://github.com/quictls/openssl.git quic-openssl
retry wget -q http://nginx.org/download/njs-${NJS_VERSION}.tar.gz
tar -xzf njs-${NJS_VERSION}.tar.gz

# ─────────────── Compilar biblioteca Brotli estática ───────────────
pushd ngx_brotli/deps/brotli >/dev/null
mkdir -p out && cd out
cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
         -DCMAKE_INSTALL_PREFIX=./installed \
         -DCMAKE_C_FLAGS="-Ofast -march=native -mtune=native"
make brotlienc -j"$(nproc)"
strip --strip-unneeded brotli*
popd >/dev/null

# ───────────────────── Compilar NGINX ─────────────────────
cd nginx-${NGINX_VERSION}

export CFLAGS="-O3 -march=native -mtune=native -flto -fdata-sections \
               -ffunction-sections -fstack-protector-strong -D_FORTIFY_SOURCE=2"
export LDFLAGS="-Wl,--as-needed -Wl,--gc-sections -Wl,-z,relro -Wl,-z,now"

./configure \
  --prefix=/etc/nginx \
  --sbin-path=/usr/sbin/nginx \
  --conf-path=/etc/nginx/nginx.conf \
  --error-log-path=/var/log/nginx/error.log \
  --http-log-path=/var/log/nginx/access.log \
  --pid-path=/var/run/nginx.pid \
  --lock-path=/var/lock/nginx.lock \
  --user=www-data --group=www-data \
  --with-http_ssl_module \
  --with-http_v2_module \
  --with-http_v3_module \
  --with-http_dav_module \
  --with-http_realip_module \
  --with-http_stub_status_module \
  --with-http_gzip_static_module \
  --with-http_sub_module \
  --with-http_mp4_module \
  --with-http_slice_module \
  --with-http_auth_request_module \
  --with-threads --with-file-aio \
  --with-stream --with-stream_ssl_module \
  --with-compat \
  --with-openssl=../quic-openssl \
  --with-openssl-opt="enable-ktls" \
  --add-module=../ngx_brotli \
  --add-module=../headers-more-nginx-module \
  --add-module=../ngx_http_geoip2_module \
  --add-module=../pagespeed \
  --add-module=../njs-${NJS_VERSION}/nginx

make -j"$(nproc)"
make install
mkdir -p /etc/nginx/snippets         
cp -r ./nginx/snippets/* /etc/nginx/snippets/

echo "✅ NGINX compilado/instalado."

# ─────────────── GeoLite2 Country (auto-reload) ───────────────
cd /etc/nginx/geoip2
echo "🌍 Baixando GeoLite2…"
retry wget -q https://geolite.maxmind.com/download/geoip/database/GeoLite2-Country.tar.gz \
      -O GeoLite2-Country.tar.gz
tar -xzf GeoLite2-Country.tar.gz --strip-components=1 --wildcards */GeoLite2-Country.mmdb
rm GeoLite2-Country.tar.gz

# ─────────────── nginx.conf (remoto ou local embed) ───────────────
if [[ -n "$NGINX_CONF_URL" ]]; then
  echo "🌐 Usando nginx.conf de $NGINX_CONF_URL"
  curl -fsSL "$NGINX_CONF_URL" -o /etc/nginx/nginx.conf
else
  echo "📦 Usando nginx.conf local de ./nginx/conf.d/nginx.conf"
  cp ./nginx/conf.d/nginx.conf /etc/nginx/nginx.conf
fi



# ─────────────── Limpeza de pacotes de build ───────────────
echo "🧹 Limpando ambiente de build…"
apt purge -y build-essential git wget curl libtool automake autoconf cmake \
              zlib1g-dev libpcre3-dev libmaxminddb-dev libgeoip-dev \
              libnghttp3-dev libngtcp2-dev pkg-config libssl-dev libgd-dev uuid-dev
apt autoremove -y --purge && apt clean
rm -rf /var/lib/apt/lists/* "$BUILD_DIR"

# ─────────────── Teste e subida do NGINX ───────────────
echo "🔄 Testando configuração…"
nginx -t
echo "🚀 Subindo NGINX (daemon off)…"
exec nginx -g 'daemon off;'
